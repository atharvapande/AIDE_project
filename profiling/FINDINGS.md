# Profiling findings (scale 1, run 2026-10-31)

Script: `profiling/profile_raw.py` (run from repo root). Verdict column = what the data showed.

| # | Hypothesis | Verdict | Evidence |
|---|---|---|---|
| 1 | Truncated telemetry file crashes whole-feed read | CONFIRMED | `reefer_telemetry/dt=2025-07-14/part-00000.parquet` unreadable. Manifest 3,714,871 rows vs 3,713,926 readable (945 lost) |
| 2 | POS schema drift needs union_by_name | CONFIRMED, but whole-feed read does NOT fail with union_by_name | qty non-null 2,040,631; quantity_units 2,043,369; uom only post-drift (19.0% CS) |
| 3 | POS duplicates ~2.1% | CONFIRMED | 4,084,000 rows, 4,000,000 distinct (txn_id, txn_line_no) |
| 4 | POS event_ts UTC shifts business date | REFUTED in this data | 0 rows where UTC date != IST date (UTC hours 0-17) |
| 5 | Late arrivals ~4.5% | CONFIRMED | 4.50% of rows have ingest_date != IST event date |
| 6 | POS emits all four channels (contract says MT+ecom) | CONFIRMED | GT 2.07M, MT 1.04M, HORECA 0.72M, ECOM 0.26M |
| 7 | Till channel vs outlet channel | Till channel == outlet INSERT channel for every outlet (0% mismatch) | 2,070 outlets later change channel in CDC (KP-3155) |
| 8 | COLDEYE reports F; temp_unit null ~8% | CONFIRMED | COLDEYE mean 39.6 (F), THERMLOG 4.2 (C); null unit 8% both vendors |
| 9 | Divya's "a third of trips" = unit bug | CONFIRMED | readings >8 raw: 38.3%; after F->C: 7.2% |
| 10 | Firmware 2.1.4 +7h clock skew | CONFIRMED | 98,885 of 338,713 2.1.4 rows cross the dt boundary; 0 for other firmware |
| 11 | Telemetry dups ~3.2% | CONFIRMED | 3,713,926 vs 3,598,770 distinct |
| 12 | GW-017 outage 2026-02-11/12 | CONFIRMED | ~180-200 rows/day on neighbouring days, none on 11th/12th |
| 13 | WMS order stitching | PROBLEM | 4.72 scans/order; only 393 of 317,082 orders have PICK and DISPATCH under one warehouse. Dock-to-dispatch per order is essentially not computable |
| 14 | CDC delete tombstone trap | CONFIRMED | all 2,880 deleted orders also have later U rows; D carries the insert op_ts |
| 15 | source_system stable per order | REFUTED | 230,240 orders have >1 source_system across versions; need a defined rule (e.g. at insert) |
| 16 | PARTNER_API inflated 8.5% | CONFIRMED | mean order value 261,390 vs ~241,000 for the other two sources |
| 17 | UOM table incomplete | CONFIRMED | 1,054 of 1,100 SKUs |
| 18 | Legacy report vs raw | Not reconcilable | legacy 18-month total INR 4.59B (random per channel-week) vs deduped POS qty*price INR 5.51B; bridge needed |
| 19 | Manifest | Covers 3 feeds, not ERP; counts include the truncated file | |

Open: POS unit_price vs uom (CS rows) ambiguity; trip definition for telemetry (no trip id, no carrier link); service level has no delivery date.

## Added during pipeline build (2026-10-31)

| Finding | Evidence |
|---|---|
| Price is per EACH even on case (CS) rows | mean unit_price 211.76 (CS) vs 211.72 (EA). Tax on CS rows = 12% of price x raw qty, so tax and discount are understated on CS rows (they use the case count, not eaches). Limitation, not corrected |
| Order outlet_code is unstable across versions | 319,952 of 320,000 orders have more than one outlet_code across their versions. Order-level outlet is unreliable; the latest version is used and the insert version is kept alongside |
| Master deletes are not terminal | 33 of 48 deleted outlets have updates after the delete. Deletes recorded as deleted_at, not as a version |
| 86 outlet versions share (key, op_ts) with another | higher __seq wins, the other goes to dq.quarantine |
| Clock-skew correction is exact | subtracting 7h for firmware 2.1.4 restores the dt date on 100% of rows |
| Pre-drift POS rows have no uom | 1,998,980 rows assumed EA (flagged uom_assumed) |
| Feed-level missing-day detection finds nothing | the only outage (GW-017, 2026-02-11 and 12) is visible only at gateway x day grain |

## Price basis and magnitude (2026-10-31, after the mart build)

| Finding | Evidence |
|---|---|
| Per-each pricing creates a false jump at the schema change | monthly gross INR ~30 crore to ~115 crore in 2025-10 under qty_eaches x price; flat (~30 crore) under qty x price. Default is qty x price |
| Three magnitudes disagree | POS gross ~370 crore a year (qty x price); order header ~5,100 crore a year (320k orders x ~241k mean); the brief says ~900 crore a year. None reconciles to another |
| Legacy report has no relationship to raw data | weekly correlation with rebuilt gross is -0.04; legacy 18-month total INR 458.9 crore against 544.8 crore Kestrel for the same weeks |
| Channel by outlet master vs till channel moves a large share of sales | ECOM 35.7 crore at till, 98.5 crore as-of; GT 281.7 crore at till, 186.5 crore as-of |
| Trip breach rate is a definition artifact | 75% of device-days breach; reading-level excursion rate is 7.2% in every month and every warehouse |
| Cycle time is unusable at order level | 8 of ~141,000 scanned orders per warehouse have receive-to-dispatch within 24 hours; uncapped median ~3,900 hours |
| No order is ever DELIVERED | status mix is one third each CONFIRMED, PICKED, DISPATCHED |
