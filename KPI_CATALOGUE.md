# KPI catalogue

Generated from `catalogue/kpi_catalogue.csv` by `python -m kestrel catalogue`. Edit the CSV, not this file.

Owners are proposed and need confirming. Confidence is how far the figure can be trusted given the source data.

| ID | KPI | Confidence | Owner (proposed) | Query |
|---|---|---|---|---|
| K01 | Gross sales (INR) | MEDIUM | Anand Krishnamurthy, Group CFO | `q01_gross_sales_by_channel` |
| K02 | Net sales (INR) | MEDIUM | Anand Krishnamurthy, Group CFO | `q01_gross_sales_by_channel` |
| K03 | Units sold (eaches) | MEDIUM (post 2025-10), LOW (earlier) | Anand Krishnamurthy, Group CFO | `q03_units_sold_eaches` |
| K04 | Basket count | LOW | Anand Krishnamurthy, Group CFO | `(column baskets in mart.sales_daily_channel)` |
| K05 | Cold chain excursion rate (reading level) | HIGH for the rate, NOT AVAILABLE by carrier | Divya Raghavan, Head of Supply Chain Operations | `q04_cold_chain_breach, q04b_cold_chain_by_warehouse` |
| K06 | Cold chain trip breach rate (proxy) | LOW | Divya Raghavan, Head of Supply Chain Operations | `q04_cold_chain_breach` |
| K07 | Dock-to-dispatch cycle time (hours) | LOW | Divya Raghavan, Head of Supply Chain Operations | `q05_dock_to_dispatch` |
| K08 | Outlet channel changes | HIGH | Anand Krishnamurthy, Group CFO | `q06_outlet_channel_changes` |
| K09 | Order value by source system | MEDIUM | Anand Krishnamurthy, Group CFO | `q07_order_value_by_source` |
| K10 | Service level (on-time delivery) | NOT COMPUTABLE | Divya Raghavan, Head of Supply Chain Operations | `q09_service_level` |
| K11 | Gap to the Finance weekly report | MEDIUM | Anand Krishnamurthy, Group CFO | `q02_finance_reconciliation, q02b_finance_bridge_weekly` |
| K12 | Missing data | HIGH | Data platform (no owner today) | `q08_missing_data` |

## K01. Gross sales (INR)

- **Definition:** Value of goods sold at list line price before discount and tax: quantity sold x unit price, summed. Channel is the outlet's channel on the day of the sale.
- **Grain:** Sale line; reported by day x channel, rolled up to week, month, fiscal quarter
- **Filters and exclusions:** Duplicate lines removed (key txn_id + txn_line_no). Sale date is the IST date of event_ts, not the ingest date. Fiscal year runs April to March.
- **Source feeds:** pos_transactions; erp_cdc/outlet_master (channel as-of); reference/fiscal_calendar
- **Owner (proposed):** Anand Krishnamurthy, Group CFO
- **Known limitations:** Price basis is a judgement: unit_price is treated as price per sale unit (per case on case lines). Pricing per each would make monthly sales jump 3.7x at the 2025-10 schema change; shown as gross_sales_inr_alt_basis. Channel by outlet master moves a large share of sales versus the till channel.
- **Query:** `q01_gross_sales_by_channel`
- **Confidence:** MEDIUM

## K02. Net sales (INR)

- **Definition:** Gross sales minus line discount, before tax.
- **Grain:** Sale line; day x channel
- **Filters and exclusions:** As K01.
- **Source feeds:** pos_transactions; erp_cdc/outlet_master
- **Owner (proposed):** Anand Krishnamurthy, Group CFO
- **Known limitations:** Discount_amount on case lines is computed by the source on the case count, as tax is. Not corrected.
- **Query:** `q01_gross_sales_by_channel`
- **Confidence:** MEDIUM

## K03. Units sold (eaches)

- **Definition:** Quantity sold expressed in single units: each lines as captured, case lines multiplied by eaches per case (uom_conversion table, falling back to product master case_pack).
- **Grain:** Sale line; reported by month
- **Filters and exclusions:** Duplicates removed. Sale date in IST.
- **Source feeds:** pos_transactions; reference/uom_conversion; erp_cdc/product_master
- **Owner (proposed):** Anand Krishnamurthy, Group CFO
- **Known limitations:** Before 2025-10-01 the feed has no unit-of-measure column, so those lines are assumed to be eaches. Months before October 2025 are therefore not comparable with later months. 46 SKUs are missing from the conversion table and use case_pack.
- **Query:** `q03_units_sold_eaches`
- **Confidence:** MEDIUM (post 2025-10), LOW (earlier)

## K04. Basket count

- **Definition:** Distinct shopper baskets: distinct (basket_id, outlet) within a sale day.
- **Grain:** Day x channel
- **Filters and exclusions:** As K01.
- **Source feeds:** pos_transactions
- **Owner (proposed):** Anand Krishnamurthy, Group CFO
- **Known limitations:** basket_id alone spans several outlets and days for about 65% of baskets, so it cannot identify a basket by itself. The composite is a best effort and may still merge two shoppers.
- **Query:** `(column baskets in mart.sales_daily_channel)`
- **Confidence:** LOW

## K05. Cold chain excursion rate (reading level)

- **Definition:** Readings above 8 C divided by valid readings, after converting Fahrenheit to Celsius and correcting device clocks. The contract defines an excursion as any reading above the 2-8 C band; readings below 2 C are tracked separately and not counted.
- **Grain:** Reading; reported by month, warehouse, vendor
- **Filters and exclusions:** Duplicate readings removed. Null readings excluded from the denominator. Every reefer reading is treated as chilled (no chilled flag exists).
- **Source feeds:** reefer_telemetry; reference/warehouse_master
- **Owner (proposed):** Divya Raghavan, Head of Supply Chain Operations
- **Known limitations:** Raw readings show about 38% over 8, which is the Fahrenheit vendor read as Celsius; the corrected rate is about 7.2%. Carrier breakdown is impossible: nothing in telemetry links to a carrier. 8% of rows have no unit and use the vendor to infer it. Gateway outages create gaps, not nulls.
- **Query:** `q04_cold_chain_breach, q04b_cold_chain_by_warehouse`
- **Confidence:** HIGH for the rate, NOT AVAILABLE by carrier

## K06. Cold chain trip breach rate (proxy)

- **Definition:** Share of device-days with at least one reading above 8 C. A device-day stands in for a trip.
- **Grain:** Device-day; reported by month
- **Filters and exclusions:** As K05.
- **Source feeds:** reefer_telemetry
- **Owner (proposed):** Divya Raghavan, Head of Supply Chain Operations
- **Known limitations:** There is no trip id, and one device-day carries about 19 readings and many route codes, so this measures how long a device was watched, not trips. About 75% of device-days breach. Do not quote it as a trip rate. Needs a trip table from operations.
- **Query:** `q04_cold_chain_breach`
- **Confidence:** LOW

## K07. Dock-to-dispatch cycle time (hours)

- **Definition:** Hours from the first RECEIVE scan to the last DISPATCH scan for the same order at the same warehouse, median by warehouse. Pairs over a cap (default 24 hours) are treated as unmatched scans.
- **Grain:** Order x warehouse; reported by warehouse
- **Filters and exclusions:** Missing scans (about 6.5% never emitted) leave orders unmeasured. Dispatch before receive is excluded.
- **Source feeds:** wms_scan_events; reference/warehouse_master
- **Owner (proposed):** Divya Raghavan, Head of Supply Chain Operations
- **Known limitations:** Scans of one order fall on about 4.7 different days and only a small share of orders has both scans at one site. The uncapped median is thousands of hours, which is not real. Result is indicative only and coverage is reported beside it. Timestamps are site local (all Asia/Kolkata).
- **Query:** `q05_dock_to_dispatch`
- **Confidence:** LOW

## K08. Outlet channel changes

- **Definition:** Outlets whose master channel changed between versions, with the date of change and the old and new channel.
- **Grain:** Outlet x change event
- **Filters and exclusions:** Master inserts and updates only. A delete does not create a version.
- **Source feeds:** erp_cdc/outlet_master
- **Owner (proposed):** Anand Krishnamurthy, Group CFO
- **Known limitations:** Change time is the commit time in the ERP (UTC). Order of changes uses (op_ts, seq), never the extract date.
- **Query:** `q06_outlet_channel_changes`
- **Confidence:** HIGH

## K09. Order value by source system

- **Definition:** Gross order value from the order header, by source system, on the latest version of each order. A freight-adjusted value divides PARTNER_API rows by 1.085.
- **Grain:** Order
- **Filters and exclusions:** Deleted orders excluded (a delete is terminal).
- **Source feeds:** erp_cdc/sales_order_header
- **Owner (proposed):** Anand Krishnamurthy, Group CFO
- **Known limitations:** The sources are not comparable as reported: PARTNER_API runs about 8.5% high. The factor is read off the data; there are no invoices to confirm it. source_system and outlet_code change between versions of one order, so source is shown both at insert and at latest version.
- **Query:** `q07_order_value_by_source`
- **Confidence:** MEDIUM

## K10. Service level (on-time delivery)

- **Definition:** Not defined: it needs a delivery date, and none exists.
- **Grain:** Order
- **Filters and exclusions:** n/a
- **Source feeds:** sales_order_header
- **Owner (proposed):** Divya Raghavan, Head of Supply Chain Operations
- **Known limitations:** No order ever reaches DELIVERED and there is no delivery timestamp. Needs proof-of-delivery data from transport.
- **Query:** `q09_service_level`
- **Confidence:** NOT COMPUTABLE

## K11. Gap to the Finance weekly report

- **Definition:** Kestrel gross sales less the published legacy weekly figure, split into duplicates counted by the legacy method, ingest date versus sale date, and channel reclassification, plus what remains unexplained.
- **Grain:** Legacy week (7 days ending Wednesday, anchored 2025-01-01) x channel
- **Filters and exclusions:** Only weeks the legacy report covers (to 2026-06-24).
- **Source feeds:** pos_transactions; reference/legacy_finance_weekly_report
- **Owner (proposed):** Anand Krishnamurthy, Group CFO
- **Known limitations:** The legacy figures have no usable relationship to the raw feed (weekly correlation near zero). The bridge accounts for duplicates and timing only; the remainder is unexplained and cannot be closed from the data. Legacy channel is assumed to be the till channel.
- **Query:** `q02_finance_reconciliation, q02b_finance_bridge_weekly`
- **Confidence:** MEDIUM

## K12. Missing data

- **Definition:** Unreadable files, partitions short of the manifest, feed-days that are empty or under half their trailing 28-day average, and gateway-days with no readings.
- **Grain:** Feed x day; gateway x day
- **Filters and exclusions:** n/a
- **Source feeds:** all feeds; _manifest/expected_partitions.csv
- **Owner (proposed):** Data platform (no owner today)
- **Known limitations:** Feed-level volume checks do not see gateway outages: the GW-017 gap is only visible at gateway x day grain. The manifest does not cover the ERP feeds and was written before the truncated file.
- **Query:** `q08_missing_data`
- **Confidence:** HIGH
