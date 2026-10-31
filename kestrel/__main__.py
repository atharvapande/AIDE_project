import argparse
from . import build as b

ap = argparse.ArgumentParser(prog="kestrel")
sub = ap.add_subparsers(dest="cmd", required=True)
bp = sub.add_parser("build", help="raw -> stg -> core -> dq")
bp.add_argument("--data", help="data directory (default KESTREL_DATA_DIR)")
bp.add_argument("--db", help="duckdb file (default KESTREL_DB_PATH)")
qp = sub.add_parser("query", help="run a named query from queries/")
qp.add_argument("name", nargs="?", help="e.g. q01 (omit to list)")
qp.add_argument("--param", "-p", action="append", default=[], help="name=value, repeatable")
qp.add_argument("--show-sql", action="store_true")
qp.add_argument("--limit", type=int, default=60)
sub.add_parser("catalogue", help="regenerate KPI_CATALOGUE.md from catalogue/kpi_catalogue.csv")
sub.add_parser("dq", help="print data-quality summary from the built warehouse")
a = ap.parse_args()
if a.cmd == "build":
    b.build(a.data, a.db)
elif a.cmd == "dq":
    b.dq_report()
elif a.cmd == "query":
    from . import query as q
    if not a.name:
        for f in q.available():
            first = [l for l in f.read_text().splitlines() if l.startswith("-- KPI")]
            print(f"{f.stem:<36}{(first[0][3:] if first else '')[:80]}")
    else:
        q.run(a.name, dict(x.split("=", 1) for x in a.param), a.show_sql, limit=a.limit)
elif a.cmd == "catalogue":
    from . import catalogue
    catalogue.write()
