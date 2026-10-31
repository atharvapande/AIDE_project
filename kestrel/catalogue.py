"""Render catalogue/kpi_catalogue.csv to KPI_CATALOGUE.md. The CSV is the single source of truth."""
import csv

from . import config as C


def write():
    rows = list(csv.DictReader(open(C.ROOT / "catalogue" / "kpi_catalogue.csv", newline="")))
    out = ["# KPI catalogue", "",
           "Generated from `catalogue/kpi_catalogue.csv` by `python -m kestrel catalogue`. Edit the CSV, not this file.", "",
           "Owners are proposed and need confirming. Confidence is how far the figure can be trusted given the source data.", "",
           "| ID | KPI | Confidence | Owner (proposed) | Query |", "|---|---|---|---|---|"]
    for r in rows:
        out.append(f"| {r['kpi_id']} | {r['name']} | {r['confidence']} | {r['owner_proposed']} | `{r['query_file']}` |")
    for r in rows:
        out += ["", f"## {r['kpi_id']}. {r['name']}", "",
                f"- **Definition:** {r['definition']}", f"- **Grain:** {r['grain']}",
                f"- **Filters and exclusions:** {r['filters_exclusions']}", f"- **Source feeds:** {r['source_feeds']}",
                f"- **Owner (proposed):** {r['owner_proposed']}", f"- **Known limitations:** {r['known_limitations']}",
                f"- **Query:** `{r['query_file']}`", f"- **Confidence:** {r['confidence']}"]
    (C.ROOT / "KPI_CATALOGUE.md").write_text("\n".join(out) + "\n")
    print("wrote KPI_CATALOGUE.md")
