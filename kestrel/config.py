"""Settings. Reads .env (if present) without printing any value."""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _load_env():
    env = ROOT / ".env"
    if not env.exists():
        return
    for line in env.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


_load_env()


def _p(name, default):
    p = Path(os.environ.get(name, default))
    return p if p.is_absolute() else ROOT / p


DATA_DIR = _p("KESTREL_DATA_DIR", "data")
DB_PATH = _p("KESTREL_DB_PATH", "warehouse/kestrel.duckdb")
MEMORY_LIMIT = os.environ.get("KESTREL_MEMORY_LIMIT", "")      # e.g. 6GB. Empty = DuckDB default

# Judgement calls, each recorded in DECISIONS.md. Change here, rebuild.
PRICE_BASIS = os.environ.get("KESTREL_PRICE_BASIS", "each")    # each | uom
PARTNER_FREIGHT_FACTOR = float(os.environ.get("KESTREL_PARTNER_FACTOR", "1.085"))
TEMP_BAND_HI_C = 8.0            # contract: excursion = any reading above the 2-8 C band
TEMP_BAND_LO_C = 2.0
SKEW_FIRMWARE = "2.1.4"         # observed: only this firmware has a clock offset
SKEW_HOURS = 7                  # observed: corrected date matches dt partition for 100% of rows
IST_OFFSET_MIN = 330            # warehouse_master: every site is Asia/Kolkata
