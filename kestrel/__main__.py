import argparse
from . import build as b

ap = argparse.ArgumentParser(prog="kestrel")
sub = ap.add_subparsers(dest="cmd", required=True)
bp = sub.add_parser("build", help="raw -> stg -> core -> dq")
bp.add_argument("--data", help="data directory (default KESTREL_DATA_DIR)")
bp.add_argument("--db", help="duckdb file (default KESTREL_DB_PATH)")
sub.add_parser("dq", help="print data-quality summary from the built warehouse")
a = ap.parse_args()
if a.cmd == "build":
    b.build(a.data, a.db)
elif a.cmd == "dq":
    b.dq_report()
