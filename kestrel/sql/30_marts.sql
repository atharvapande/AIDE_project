-- KPI marts. Everything here reads core.* only.
CREATE OR REPLACE TABLE mart.fiscal_quarters AS
SELECT fiscal_year, fiscal_quarter, min(calendar_date) AS start_date, max(calendar_date) AS end_date,
  max(calendar_date) <= (SELECT max(sale_date) FROM core.pos_sales) AS is_complete
FROM ref.fiscal_calendar GROUP BY 1, 2;

-- Sales at day x channel grain. Channel is as-of the sale. Baskets = distinct (basket_id, outlet) within the day:
-- basket_id alone spans several outlets and days for ~65% of baskets, so it is not a shopper basket.
CREATE OR REPLACE TABLE mart.sales_daily_channel AS
SELECT sale_date, channel, strftime(sale_date, '%Y-%m') AS month, fiscal_year, fiscal_quarter,
  count(*) AS lines, count(DISTINCT (basket_id, outlet_code)) AS baskets,
  sum(gross_sales_inr) AS gross_sales_inr, sum(discount_amount) AS discount_inr,
  sum(gross_sales_inr - discount_amount) AS net_sales_inr, sum(tax_amount) AS tax_inr,
  sum(qty_eaches) AS units_eaches, sum(qty_raw) AS units_raw_as_captured,
  sum(gross_sales_inr_alt_basis) AS gross_sales_inr_alt_basis
FROM core.pos_sales GROUP BY sale_date, channel, fiscal_year, fiscal_quarter;

-- Cold chain. Reading grain is the defensible one. Device-day is only a stand-in for a trip:
-- telemetry has no trip id and route_code changes between readings of the same device-day.
CREATE OR REPLACE TABLE mart.cold_chain_monthly AS
SELECT strftime(reading_date, '%Y-%m') AS month, warehouse_code, telemetry_vendor,
  count(temp_c) AS valid_readings, count(*) FILTER (WHERE is_excursion) AS excursion_readings,
  count(*) FILTER (WHERE is_below_band) AS below_band_readings,
  count(*) FILTER (WHERE temp_c IS NULL) AS null_readings
FROM core.telemetry_reading GROUP BY ALL;

CREATE OR REPLACE TABLE mart.cold_chain_device_day AS
SELECT device_id, reading_date, strftime(reading_date, '%Y-%m') AS month, any_value(telemetry_vendor) AS vendor,
  count(temp_c) AS valid_readings, count(*) FILTER (WHERE is_excursion) AS excursion_readings,
  coalesce(bool_or(is_excursion), false) AS any_excursion,
  count(DISTINCT route_code) AS distinct_routes, count(DISTINCT warehouse_code) AS distinct_warehouses
FROM core.telemetry_reading GROUP BY device_id, reading_date;

CREATE OR REPLACE TABLE mart.wms_order_warehouse AS
SELECT order_number, warehouse_code,
  min(event_ts_local) FILTER (WHERE event_type = 'RECEIVE') AS first_receive,
  max(event_ts_local) FILTER (WHERE event_type = 'DISPATCH') AS last_dispatch,
  count(*) AS scans, count(DISTINCT event_type) AS stages_seen, count(DISTINCT scan_date) AS scan_days
FROM core.wms_scan GROUP BY 1, 2;

CREATE OR REPLACE VIEW mart.outlet_channel_changes AS
SELECT outlet_code, valid_from AS changed_at, prev_channel AS from_channel, channel AS to_channel, version_no
FROM core.outlet_version WHERE channel_changed;

CREATE OR REPLACE VIEW mart.order_fact AS
SELECT * FROM core.sales_order WHERE NOT is_deleted;

-- Bridge from the legacy Finance weekly report to the Kestrel definition, one step at a time.
-- Legacy week = 7 days ending on week_ending (anchored 2025-01-01, a Wednesday). Not ISO weeks.
-- Legacy method as documented in the generator: group by INGEST date, no dedup. Legacy channel assumed = till channel.
CREATE OR REPLACE MACRO mart.legacy_week_ending(x) AS
  DATE '2025-01-01' + 7 * CAST(ceil(date_diff('day', DATE '2025-01-01', x) / 7.0) AS INTEGER);

CREATE OR REPLACE TABLE mart.finance_bridge AS
WITH u AS (SELECT txn_id, txn_line_no, sale_date, ingest_date, till_channel, channel, gross_sales_inr FROM core.pos_sales),
dups AS (
  SELECT u.ingest_date, u.till_channel, u.gross_sales_inr
  FROM dq.quarantine q JOIN u ON q.entity_key = u.txn_id || '/' || u.txn_line_no
  WHERE q.feed = 'pos_transactions' AND q.reason = 'DUPLICATE_LINE'),
b AS (SELECT mart.legacy_week_ending(ingest_date) AS week_ending, till_channel AS channel, sum(gross_sales_inr) AS v FROM u GROUP BY 1, 2),
dp AS (SELECT mart.legacy_week_ending(ingest_date) AS week_ending, till_channel AS channel, sum(gross_sales_inr) AS v FROM dups GROUP BY 1, 2),
c AS (SELECT mart.legacy_week_ending(sale_date) AS week_ending, till_channel AS channel, sum(gross_sales_inr) AS v FROM u GROUP BY 1, 2),
d AS (SELECT mart.legacy_week_ending(sale_date) AS week_ending, channel, sum(gross_sales_inr) AS v FROM u GROUP BY 1, 2),
spine AS (
  SELECT w AS week_ending, ch AS channel
  FROM (SELECT DISTINCT week_ending AS w FROM (SELECT week_ending FROM b UNION SELECT week_ending FROM c UNION SELECT week_ending FROM ref.legacy_finance_weekly)) x
  CROSS JOIN (SELECT unnest(['GT','MT','HORECA','ECOM']) AS ch) y)
SELECT s.week_ending, s.channel,
  l.gross_sales_inr AS legacy_gross_inr,
  round(coalesce(b.v, 0) + coalesce(dp.v, 0), 2) AS rebuilt_legacy_method_inr,
  round(coalesce(dp.v, 0), 2) AS duplicates_inr,
  round(coalesce(c.v, 0) - coalesce(b.v, 0), 2) AS timing_ingest_vs_event_inr,
  round(coalesce(d.v, 0) - coalesce(c.v, 0), 2) AS channel_reclass_inr,
  round(coalesce(d.v, 0), 2) AS kestrel_gross_inr,
  round(l.gross_sales_inr - (coalesce(b.v, 0) + coalesce(dp.v, 0)), 2) AS unexplained_vs_legacy_inr,
  round(l.gross_sales_inr - coalesce(d.v, 0), 2) AS total_gap_inr
FROM spine s
LEFT JOIN ref.legacy_finance_weekly l ON l.week_ending = s.week_ending AND l.channel = s.channel
LEFT JOIN b ON b.week_ending = s.week_ending AND b.channel = s.channel
LEFT JOIN dp ON dp.week_ending = s.week_ending AND dp.channel = s.channel
LEFT JOIN c ON c.week_ending = s.week_ending AND c.channel = s.channel
LEFT JOIN d ON d.week_ending = s.week_ending AND d.channel = s.channel;

CREATE OR REPLACE TABLE mart.kpi_catalogue AS SELECT * FROM read_csv('{{ROOT}}/catalogue/kpi_catalogue.csv');
