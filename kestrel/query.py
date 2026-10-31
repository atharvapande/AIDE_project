"""Run a named query from queries/ with parameters. Always prints the SQL it ran (--show-sql) on request."""
import re
from pathlib import Path

import duckdb

from . import config as C

QDIR = C.ROOT / "queries"


def available():
    return sorted(p for p in QDIR.glob("q*.sql"))


def find(name):
    hits = [p for p in available() if p.stem == name or p.stem.startswith(name + "_") or p.stem.startswith(name)]
    exact = [p for p in hits if p.stem == name or p.stem.startswith(name + "_")]
    hits = exact or hits
    if len(hits) != 1:
        raise SystemExit(f"query '{name}' matches {len(hits)} files: {[h.stem for h in hits]}")
    return hits[0]


def declared_params(sql):
    out = {}
    for m in re.finditer(r"^--\s*@param\s+(\w+)\s*=\s*(.+?)\s*$", sql, re.M):
        out[m.group(1)] = None if m.group(2).upper() == "NULL" else m.group(2)
    return out


def run(name, params=None, show_sql=False, db=None, limit=60):
    path = find(name)
    sql = path.read_text()
    p = declared_params(sql)
    for k, v in (params or {}).items():
        if k not in p:
            raise SystemExit(f"unknown parameter '{k}' for {path.stem}. Declared: {list(p) or 'none'}")
        p[k] = v
    if show_sql:
        print(f"-- {path.name}  params={p}\n{sql}")
    con = duckdb.connect(str(db or C.DB_PATH), read_only=True)
    df = con.execute(sql, p).df() if p else con.execute(sql).df()
    con.close()
    import pandas as pd
    with pd.option_context("display.width", 220, "display.max_columns", 30, "display.max_colwidth", 60):
        print(df.head(limit).to_string(index=False))
    if len(df) > limit:
        print(f"... {len(df) - limit} more rows (use --limit)")
    return df
