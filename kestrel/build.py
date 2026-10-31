"""End-to-end build: inventory the raw files, then run the numbered SQL scripts in order."""
import re, time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import duckdb
import pandas as pd
import pyarrow.parquet as pq

from . import config as C

SQL_DIR = Path(__file__).parent / "sql"
FEEDS = {  # name -> (relative dir, partition column)
    "pos_transactions": ("raw/pos_transactions", "ingest_date"),
    "reefer_telemetry": ("raw/reefer_telemetry", "dt"),
    "wms_scan_events": ("raw/wms_scan_events", "dt"),
    "erp_outlet_master": ("raw/erp_cdc/outlet_master", "extract_date"),
    "erp_product_master": ("raw/erp_cdc/product_master", "extract_date"),
    "erp_sales_order_header": ("raw/erp_cdc/sales_order_header", "extract_date"),
}


def _probe(path):
    """Row count from the parquet footer. A truncated file has no footer and raises."""
    try:
        return path, pq.ParquetFile(path).metadata.num_rows, "OK", None
    except Exception as e:  # noqa: BLE001 - any failure means the file is unusable
        return path, None, "CORRUPT", str(e)[:200]


def inventory(data_dir):
    rows = []
    for feed, (rel, _) in FEEDS.items():
        files = sorted((data_dir / rel).glob("*/*.parquet"))
        with ThreadPoolExecutor(8) as ex:
            for path, n, status, err in ex.map(_probe, files):
                rows.append({"feed": feed, "partition": path.parent.name, "file": str(path),
                             "rows": n, "status": status, "error": err})
    return pd.DataFrame(rows)


def _lit(files):
    return "[" + ",".join("'" + f.replace("'", "''") + "'" for f in files) + "]"


def _reader(inv, feed):
    ok = inv[(inv.feed == feed) & (inv.status == "OK")]["file"].tolist()
    if not ok:
        raise SystemExit(f"no readable files for feed {feed}")
    return (f"read_parquet({_lit(ok)}, union_by_name=true, hive_partitioning=true, "
            f"filename=true, file_row_number=true)")


def build(data=None, db=None):
    data_dir = Path(data).resolve() if data else C.DATA_DIR
    db_path = Path(db).resolve() if db else C.DB_PATH
    if not (data_dir / "raw").is_dir():
        raise SystemExit(f"{data_dir}/raw not found. Generate it: python3 generate_dataset.py --scale 1 --out data")
    db_path.parent.mkdir(parents=True, exist_ok=True)
    if db_path.exists():
        db_path.unlink()
    con = duckdb.connect(str(db_path))
    tmp = db_path.parent / "tmp"
    tmp.mkdir(exist_ok=True)
    con.execute(f"SET temp_directory='{tmp}'")
    if C.MEMORY_LIMIT:
        con.execute(f"SET memory_limit='{C.MEMORY_LIMIT}'")
    for s in ("raw", "stg", "ref", "core", "dq", "mart"):
        con.execute(f"CREATE SCHEMA IF NOT EXISTS {s}")

    t0 = time.time()
    print("inventory: probing parquet footers ...", flush=True)
    inv = inventory(data_dir)
    con.register("inv_df", inv)
    con.execute("CREATE TABLE raw.file_inventory AS SELECT * FROM inv_df")
    con.unregister("inv_df")
    bad = inv[inv.status != "OK"]
    print(f"  {len(inv):,} files, {len(bad)} unreadable (quarantined at file level)", flush=True)
    for f in bad["file"]:
        print("   QUARANTINED FILE:", f)

    params = {
        "DATA": str(data_dir).replace("'", "''"),
        "POS": _reader(inv, "pos_transactions"), "TEL": _reader(inv, "reefer_telemetry"),
        "WMS": _reader(inv, "wms_scan_events"), "OUT": _reader(inv, "erp_outlet_master"),
        "PROD": _reader(inv, "erp_product_master"), "SOH": _reader(inv, "erp_sales_order_header"),
        "PARTNER_FACTOR": repr(C.PARTNER_FREIGHT_FACTOR),
        "TEMP_HI": repr(C.TEMP_BAND_HI_C), "TEMP_LO": repr(C.TEMP_BAND_LO_C),
        "SKEW_FW": C.SKEW_FIRMWARE, "SKEW_HOURS": str(C.SKEW_HOURS), "IST_MIN": str(C.IST_OFFSET_MIN),
        "GROSS_QTY": "qty_eaches" if C.PRICE_BASIS == "each" else "qty_raw",
        "ALT_QTY": "qty_raw" if C.PRICE_BASIS == "each" else "qty_eaches",
        "ROOT": str(C.ROOT).replace("'", "''"),
    }
    print(f"price basis: {C.PRICE_BASIS}", flush=True)
    for script in sorted(SQL_DIR.glob("*.sql")):
        sql = re.sub(r"\{\{(\w+)\}\}", lambda m: params[m.group(1)], script.read_text())
        t = time.time()
        for stmt in [s for s in re.split(r";\s*\n", sql) if s.strip()]:
            con.execute(stmt)
        print(f"  {script.name:<28} {time.time() - t:6.1f}s", flush=True)

    print("\ntable row counts")
    for sch, tbl in con.execute("SELECT table_schema, table_name FROM information_schema.tables "
                                "WHERE table_schema IN ('stg','core','dq','mart','ref') "
                                "ORDER BY 1,2").fetchall():
        n = con.execute(f"SELECT count(*) FROM {sch}.{tbl}").fetchone()[0]
        print(f"  {sch}.{tbl:<34}{n:>12,}")
    print(f"\nbuilt {db_path} in {time.time() - t0:.0f}s")
    con.close()
    dq_report(db_path)


def dq_report(db=None):
    db_path = Path(db) if db else C.DB_PATH
    con = duckdb.connect(str(db_path), read_only=True)
    print("\n=== data-quality assertions ===")
    for r in con.execute("SELECT severity, check_name, expected, actual, passed FROM dq.assertions "
                         "ORDER BY passed, severity, check_name").fetchall():
        print(f"  [{'PASS' if r[4] else 'FAIL'}][{r[0]:<5}] {r[1]:<44} expected={r[2]}  actual={r[3]}")
    print("\n=== manifest reconciliation (non-OK partitions) ===")
    for r in con.execute("SELECT feed, partition, status, expected_rows, readable_rows, missing_rows "
                         "FROM dq.manifest_recon WHERE status <> 'OK' ORDER BY 1,2 LIMIT 20").fetchall():
        print("  ", r)
    print("\n=== gateway-days with zero rows ===")
    for r in con.execute("SELECT * FROM dq.gateway_day_gaps ORDER BY 1,2 LIMIT 20").fetchall():
        print("  ", r)
    print("\n=== feed-days missing or anomalously low ===")
    for r in con.execute("SELECT feed, d, rows, round(trailing_avg,0) FROM dq.missing_days "
                         "ORDER BY feed, d LIMIT 40").fetchall():
        print("  ", r)
    con.close()
