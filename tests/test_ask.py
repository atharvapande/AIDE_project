"""Guardrail and routing tests for `kestrel ask`. No API key or network needed: the model is a stub.
Run from the repo root:  python tests/test_ask.py   (needs a built warehouse for the routing tests)."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from kestrel import ask as A                      # noqa: E402
from kestrel import config as C                   # noqa: E402

fails = 0


def check(name, cond):
    global fails
    print(("PASS " if cond else "FAIL ") + name)
    fails += 0 if cond else 1


def rejected(sql):
    try:
        A.validate_sql(sql)
        return False
    except A.Rejected:
        return True


# --- validator: things that must be refused
check("drop table refused", rejected("DROP TABLE core.pos_sales"))
check("second statement refused", rejected("select 1; drop table x"))
check("delete refused", rejected("delete from core.pos_sales"))
check("create refused", rejected("create table t as select 1"))
check("attach refused", rejected("attach 'x.db'"))
check("copy refused", rejected("copy (select 1) to 'x.csv'"))
check("read_parquet refused", rejected("select * from read_parquet('data/raw/x/*.parquet')"))
check("read_csv refused", rejected("select * from read_csv('/etc/passwd')"))
check("staging schema refused", rejected("select * from stg.pos_transactions"))
check("raw schema refused", rejected("select * from raw.file_inventory"))
check("pragma refused", rejected("pragma database_list"))
check("non-select refused", rejected("show tables"))
check("comment-hidden keyword still caught", rejected("select 1 /* ok */ ; update x set a=1"))
# --- validator: things that must pass
check("plain select passes", not rejected("select count(*) from core.pos_sales"))
check("cte passes", not rejected("with a as (select 1 x) select * from a"))
check("keyword inside string literal passes", not rejected("select 'drop table' as note"))
check("replace() function passes", not rejected("select replace(channel, 'GT', 'General') from core.pos_sales"))
check("trailing semicolon passes", not rejected("select 1;"))

# --- end to end with a stub model, against a built warehouse
if Path(C.DB_PATH).exists():
    class Stub:
        def __init__(self, replies):
            self.replies, self.chat = list(replies), self
            self.completions = self

        def create(self, **kw):
            text = self.replies.pop(0)
            return type("R", (), {"choices": [type("C", (), {"message": type("M", (), {"content": text})()})()]})()

    def run(replies, q="test"):
        lines = []
        rec = A.ask(q, client=Stub(replies), out=lines.append)
        return rec, "\n".join(lines)

    rec, txt = run([json.dumps({"mode": "library", "interpretation": "last quarter", "query": "q01_gross_sales_by_channel", "params": {}})])
    check("library route runs and shows SQL", rec["error"] is None and "SQL run" in txt and "mart.sales_daily_channel" in txt)

    rec, txt = run([json.dumps({"mode": "library", "interpretation": "last quarter", "query": "q01_gross_sales_by_channel",
                                "params": {"fiscal_year": None, "fiscal_quarter": "null"}})])
    check("null params from the model do not become the text 'None'", rec["rows"] and rec["rows"] > 0)

    ctx = A.context()[3]
    check("prompt facts name the latest complete quarter", "FY27 Q1" in ctx and "2026-06" in ctx)
    rec, txt = run([json.dumps({"mode": "library", "interpretation": "last quarter", "query": "q01_gross_sales_by_channel",
                                "params": {"fiscal_year": "FY27", "fiscal_quarter": "Q1"}})])
    check("parameters are printed", "Parameters passed:" in txt and "FY27" in txt)

    rec, txt = run([json.dumps({"mode": "sql", "interpretation": "line count", "sql": "select count(*) as n from core.pos_sales"})])
    check("generated SQL runs and is printed", rec["error"] is None and "select count(*)" in txt)

    bad = json.dumps({"mode": "sql", "interpretation": "x", "sql": "drop table core.pos_sales"})
    rec, txt = run([bad, bad])
    check("destructive SQL refused after repair attempt", rec["error"] is not None and "Could not answer safely" in txt)

    good = json.dumps({"mode": "sql", "interpretation": "x", "sql": "select count(*) as n from core.pos_sales"})
    rec, txt = run([bad, good])
    check("repair attempt can recover", rec["error"] is None)

    rec, txt = run([json.dumps({"mode": "library", "interpretation": "closest KPI", "omitted": "carrier: no link",
                                "query": "q04_cold_chain_breach", "params": {}})])
    check("partial answer prints NOT ANSWERED and still runs", "NOT ANSWERED: carrier" in txt and rec["rows"] and rec["rows"] > 0)
    rec, txt = run([json.dumps({"mode": "library", "interpretation": "x", "omitted": "None.",
                                "query": "q09_service_level", "params": {}})])
    check("'None.' in omitted is not printed", "NOT ANSWERED" not in txt)
    check("worked example is in the prompt", "WORKED EXAMPLE" in A.SYSTEM and "q04_cold_chain_breach" in A.SYSTEM)

    rec, txt = run([json.dumps({"mode": "cannot_answer", "interpretation": "carrier breach", "reason": "no carrier link in telemetry"})])
    check("cannot_answer is reported, nothing run", "Cannot answer" in txt and rec["rows"] is None)

    rec, txt = run(["not json at all", "still not json"])
    check("garbage model output handled", rec["error"] is not None)
else:
    print("SKIP routing tests: build the warehouse first (python -m kestrel build)")

sys.exit(1 if fails else 0)
