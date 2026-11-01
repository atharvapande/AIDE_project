# Kestrel Provisions: analytical foundation and metric layer

A DuckDB warehouse built from the four raw feeds, with a defined KPI catalogue, a parameterised SQL library, and a
plain-English `ask` command that always shows the SQL it ran. Read `DECISIONS.md` first, then `KPI_CATALOGUE.md`.

Tested with Python 3.10 and DuckDB 1.5.6. One machine, no services. The shipped scale-1 data builds in about 35 seconds.

## Cold start

```bash
git clone https://github.com/atharvapande/AIDE_project.git && cd AIDE_project
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# 1. the data (not committed). Either copy the shipped data/ folder into the repo root, or regenerate it
#    (same seed, identical output, takes a few minutes):
python3 generate_dataset.py --scale 1 --out data

# 2. build the warehouse: raw -> stg -> core -> dq -> mart   (writes warehouse/kestrel.duckdb)
python -m kestrel build

# 3. use it
python -m kestrel query                    # list the queries
python -m kestrel query q01                # gross sales by channel, last complete fiscal quarter
python -m kestrel query q01 -p fiscal_year=FY26 -p fiscal_quarter=Q4 --show-sql
python -m kestrel dq                       # data-quality report

# 4. optional: plain-English questions (needs an OpenAI key)
cp .env.example .env                       # then put your key after OPENAI_API_KEY=
python -m kestrel ask "Units sold last month, in eaches"

python tests/test_ask.py                   # guardrail tests, no key or network needed
```

`build` always rebuilds from scratch and exits with a data-quality report. It does not stop on bad data: unreadable
files are quarantined and reported, and every dropped row is kept in `dq.quarantine` with a reason.

## Settings (`.env`, all optional)

| Variable | Default | Meaning |
|---|---|---|
| `KESTREL_DATA_DIR` | `data` | folder containing `raw/`, `reference/`, `_manifest/` |
| `KESTREL_DB_PATH` | `warehouse/kestrel.duckdb` | warehouse file |
| `KESTREL_MEMORY_LIMIT` | DuckDB default | for example `6GB`; spills to `warehouse/tmp` |
| `KESTREL_PRICE_BASIS` | `uom` | `uom`: gross = qty x unit_price. `each`: qty in eaches x unit_price. See DECISIONS |
| `KESTREL_PARTNER_FACTOR` | `1.085` | freight inflation divided out of PARTNER_API order values |
| `OPENAI_API_KEY`, `OPENAI_MODEL` | empty, `gpt-4o-mini` | only for `ask` |

## Layout

```
kestrel/            python package: build.py (runner), query.py, ask.py, catalogue.py
kestrel/sql/        numbered scripts, run in order. 02-05 staging, 10-14 core, 20 data quality, 30 marts
queries/            the SQL library (11 files, q01 ... q09), parameters declared in a header comment
catalogue/          kpi_catalogue.csv is the source; KPI_CATALOGUE.md is generated from it
profiling/          profile_raw.py and FINDINGS.md: evidence behind each data decision
tests/              ask guardrail and routing tests
generate_dataset.py the assignment generator, unchanged
```

Warehouse schemas: `raw` file inventory, `stg` typed with lineage, `core` deduplicated facts and point-in-time
dimensions, `dq` checks and quarantine, `mart` KPI tables, `ref` reference files.

## Tracing a figure to its row

Every `stg` and `core` row carries `_src_file` and `_src_row`. Example:

```sql
SELECT txn_id, gross_sales_inr, _src_file, _src_row FROM core.pos_sales WHERE sale_date = '2026-06-30' LIMIT 5;
```

Rows removed as duplicates are in `dq.quarantine` (feed, reason, key, source file, source row).

## Regenerating the catalogue

```bash
python -m kestrel catalogue     # rewrites KPI_CATALOGUE.md from catalogue/kpi_catalogue.csv
```

## Troubleshooting

- `data/raw not found`: step 1 above.
- `ask` says the key is empty: edit `.env`. The file is git-ignored.
- Out of memory on a small machine: set `KESTREL_MEMORY_LIMIT` (for example `3GB`) in `.env`.
