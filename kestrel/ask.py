"""Ask a question in plain English. The model never produces numbers or prose answers: it either picks a vetted
query from queries/ with parameters, or writes one read-only SELECT. Either way the SQL is printed before the
result, and every request is logged to warehouse/ask_log.jsonl."""
import json
import os
import re
import time

import duckdb

from . import config as C
from . import query as Q

ROW_CAP = 200
BANNED = re.compile(
    r"\b(insert|update|delete|drop|create|alter|attach|detach|copy|pragma|install|load|call|set|export|import|"
    r"vacuum|truncate|checkpoint|grant|use|read_csv|read_csv_auto|read_parquet|read_json|read_text|glob|"
    r"parquet_scan|httpfs|getenv|current_setting)\b", re.I)
BLOCKED_SCHEMAS = re.compile(r"\b(stg|raw)\s*\.", re.I)
ALLOWED_TABLES = """
SELECT table_schema, table_name FROM information_schema.tables
WHERE (table_schema = 'mart') OR (table_schema = 'ref')
   OR (table_schema = 'core' AND table_name IN ('pos_sales','telemetry_reading','wms_scan','sales_order',
        'outlet_version','outlet_current','product_current'))
   OR (table_schema = 'dq' AND table_name IN ('manifest_recon','missing_days','gateway_day_gaps','assertions','row_accounting'))
ORDER BY 1, 2"""


class Rejected(Exception):
    pass


def _strip(sql):
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    sql = re.sub(r"--[^\n]*", " ", sql)
    return re.sub(r"'(?:[^']|'')*'", "''", sql)


def validate_sql(sql):
    """Raise Rejected unless sql is a single read-only SELECT over the allowed schemas."""
    body = _strip(sql).strip().rstrip(";").strip()
    if not body:
        raise Rejected("empty SQL")
    if ";" in body:
        raise Rejected("more than one statement")
    if not re.match(r"(select|with)\b", body, re.I):
        raise Rejected("only SELECT / WITH queries are allowed")
    m = BANNED.search(body)
    if m:
        raise Rejected(f"keyword not allowed: {m.group(1)}")
    if BLOCKED_SCHEMAS.search(body):
        raise Rejected("raw and staging schemas are not queryable here; use mart, core, ref or dq")
    return sql.strip().rstrip(";")


def _connect(db=None):
    return duckdb.connect(str(db or C.DB_PATH), read_only=True, config={"enable_external_access": False})


def run_sql(sql, db=None):
    sql = validate_sql(sql)
    con = _connect(db)
    try:
        con.execute("EXPLAIN " + sql)                       # catches binder errors before running
        df = con.execute(f"SELECT * FROM ({sql}) LIMIT {ROW_CAP}").df()
    finally:
        con.close()
    return sql, df


def context(db=None):
    con = _connect(db)
    tabs = con.execute(ALLOWED_TABLES).fetchall()
    lines = []
    for sch, t in tabs:
        cols = con.execute("SELECT column_name || ' ' || data_type FROM information_schema.columns "
                           "WHERE table_schema = ? AND table_name = ? ORDER BY ordinal_position", [sch, t]).fetchall()
        lines.append(f"{sch}.{t}({', '.join(c[0] for c in cols)})")
    cat = con.execute("SELECT kpi_id, name, definition, known_limitations, query_file, confidence "
                      "FROM mart.kpi_catalogue ORDER BY 1").fetchall()
    data_end = con.execute("SELECT max(sale_date) FROM core.pos_sales").fetchone()[0]
    fq = con.execute("SELECT fiscal_year || ' ' || fiscal_quarter || ' (' || start_date || ' to ' || end_date || ')' "
                     "FROM mart.fiscal_quarters WHERE is_complete ORDER BY end_date DESC LIMIT 1").fetchone()[0]
    lm = con.execute("SELECT CASE WHEN max(sale_date) = last_day(max(sale_date)) THEN strftime(max(sale_date), '%Y-%m') "
                     "ELSE strftime(max(sale_date) - INTERVAL 1 MONTH, '%Y-%m') END FROM core.pos_sales").fetchone()[0]
    con.close()
    lib = []
    for f in Q.available():
        txt = f.read_text()
        head = " ".join(l[3:].strip() for l in txt.splitlines() if l.startswith("--") and "@param" not in l)[:420]
        lib.append(f"- {f.stem} params={list(Q.declared_params(txt)) or 'none'}: {head}")
    kpis = [f"- {k}: {n}. {d} LIMITS: {lim} [confidence {conf}; library: {qf}]" for k, n, d, lim, qf, conf in cat]
    facts = f"Data ends {data_end}. Latest COMPLETE fiscal quarter: {fq}. Last complete calendar month: {lm}."
    return "\n".join(lines), "\n".join(lib), "\n".join(kpis), facts


SYSTEM = """You answer questions about Kestrel Provisions (food distributor, India) using ONLY the tables and
queries given. You never state numbers yourself: you return JSON and the system runs it.

Reply with one JSON object and nothing else:
{"mode": "library" | "sql" | "cannot_answer",
 "interpretation": "one sentence: how you read the question, including any assumption",
 "query": "<library query name, mode=library only>",
 "params": {"<name>": "<value>"},
 "sql": "<one DuckDB SELECT, mode=sql only>",
 "reason": "<mode=cannot_answer only: what data is missing>"}

Rules:
- Prefer mode=library when a library query answers the question. Use params exactly as declared.
- mode=sql: one read-only DuckDB SELECT over the listed tables. Prefer mart.* tables. For orders use mart.order_fact
  (deleted orders already removed). Sales channel is core.pos_sales.channel (as of the sale), not till_channel.
- FACTS: {facts}
- Fiscal year runs April to March (FY27 = Apr 2026 to Mar 2027). Never say the fiscal year ends in June.
- When the question says last, latest or most recent period, LEAVE THE PERIOD PARAMS NULL: the library query already
  resolves the default to the latest complete period. Set a period param only when the user names one explicitly.
- If you write SQL yourself, use the dates in FACTS, not today's date.
- If only PART of a question can be answered (for example by month but not by carrier), answer that part with the
  closest defined KPI and say in interpretation exactly what was left out and why. Use cannot_answer only when
  nothing relevant can be computed (for example service level). Never invent a link between tables that the KPI
  notes say does not exist (telemetry has no carrier or trip id).
- Low-confidence KPIs (trip breach, cycle time) may be answered, but say they are low confidence in interpretation.
- Money is INR. Crore = 10,000,000.

TABLES
{tables}

LIBRARY QUERIES
{library}

KPI NOTES
{kpis}
"""


def _llm(client, model, messages):
    kw = dict(model=model, messages=messages, response_format={"type": "json_object"})
    try:
        r = client.chat.completions.create(temperature=0, **kw)
    except Exception as e:  # noqa: BLE001 - some models reject temperature; retry once without it
        if "temperature" not in str(e).lower():
            raise
        r = client.chat.completions.create(**kw)
    return r.choices[0].message.content


def _parse(text):
    try:
        obj = json.loads(text)
    except json.JSONDecodeError:
        m = re.search(r"\{.*\}", text, re.S)
        if not m:
            raise Rejected("model did not return JSON")
        obj = json.loads(m.group(0))
    if obj.get("mode") not in ("library", "sql", "cannot_answer"):
        raise Rejected(f"bad mode: {obj.get('mode')}")
    return obj


def ask(question, client=None, db=None, model=None, out=print):
    model = model or os.environ.get("OPENAI_MODEL", "gpt-4o-mini")
    if client is None:
        if not os.environ.get("OPENAI_API_KEY"):
            raise SystemExit("OPENAI_API_KEY is empty. Add it to .env (see .env.example) and run again.")
        from openai import OpenAI
        client = OpenAI()
    tables, lib, kpis, facts = context(db)
    sysmsg = SYSTEM.replace("{facts}", facts).replace("{tables}", tables).replace("{library}", lib).replace("{kpis}", kpis)
    msgs = [{"role": "system", "content": sysmsg}, {"role": "user", "content": question}]
    rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "question": question, "model": model}
    obj, df, shown_sql, err = None, None, None, None
    for attempt in (1, 2):                                  # one repair attempt on a rejected or failing query
        try:
            obj = _parse(_llm(client, model, msgs))
            if obj["mode"] == "sql":
                shown_sql, df = run_sql(obj.get("sql", ""), db)
            elif obj["mode"] == "library":
                f = Q.find(obj.get("query", ""))
                txt = f.read_text()
                declared = Q.declared_params(txt)
                params = {k: str(v) for k, v in (obj.get("params") or {}).items()
                          if k in declared and v is not None and str(v).strip().lower() not in ("", "null", "none")}
                p = {**declared, **params}
                con = _connect(db)
                try:
                    df = con.execute(txt, p).df() if p else con.execute(txt).df()
                finally:
                    con.close()
                shown_sql = txt.strip()
                rec["library_params"] = p
            err = None
            break
        except (Rejected, duckdb.Error, SystemExit, KeyError, json.JSONDecodeError) as e:
            err = str(e)
            msgs += [{"role": "assistant", "content": json.dumps(obj) if obj else ""},
                     {"role": "user", "content": f"That failed: {err}. Fix it and reply with the JSON again."}]
    rec.update(mode=(obj or {}).get("mode"), error=err, sql=shown_sql, rows=None if df is None else len(df))
    try:
        log = C.DB_PATH.parent / "ask_log.jsonl"
        with open(log, "a") as fh:
            fh.write(json.dumps(rec, default=str) + "\n")
    except OSError:
        pass
    out(f"Question: {question}")
    if err:
        out(f"\nCould not answer safely: {err}")
        return rec
    out(f"Interpretation: {obj.get('interpretation', '')}")
    if obj["mode"] == "cannot_answer":
        out(f"\nCannot answer from this data: {obj.get('reason', '')}")
        return rec
    if obj["mode"] == "library":
        used = {k: v for k, v in rec.get("library_params", {}).items() if v is not None}
        out(f"Parameters passed: {used if used else 'none (query default applies)'}")
    out(f"\nSQL run ({'library ' + obj.get('query', '') if obj['mode'] == 'library' else 'generated'}):\n{shown_sql}\n")
    import pandas as pd
    with pd.option_context("display.width", 220, "display.max_columns", 30):
        out(df.head(60).to_string(index=False))
    if len(df) > 60:
        out(f"... {len(df) - 60} more rows")
    if len(df) == 0:
        out("(no rows returned: check the interpretation and parameters above)")
    return rec
