-- Order header current state. Versions ordered by (op_ts, seq).
-- DECISION: a delete (D) is terminal. The D record carries the insert's op_ts, so latest-by-op_ts would
-- resurrect deleted orders. Deleted orders stay in the table with is_deleted = true; marts exclude them.
-- DECISION: source_system varies between versions of the same order. Reported both at insert and latest.
-- DECISION: the PARTNER_API order value is inflated by freight (~8.5%). Reported value is kept; a
-- freight-adjusted value (reported / {{PARTNER_FACTOR}} for rows whose source is PARTNER_API) sits beside it.
-- The factor is observed from mean order values; no invoice data exists to prove it.
CREATE OR REPLACE TABLE core.sales_order AS
WITH v AS (
  SELECT *, row_number() OVER (PARTITION BY order_number ORDER BY op_ts DESC, seq DESC) AS rn
  FROM stg.cdc_order_header WHERE op IN ('I','U')
),
latest AS (SELECT * FROM v WHERE rn = 1),
ins AS (SELECT order_number, source_system AS source_system_at_insert, outlet_code AS outlet_code_at_insert,
               op_ts AS inserted_at FROM stg.cdc_order_header WHERE op = 'I'),
del AS (SELECT order_number, max(extract_date) AS deleted_extract_date FROM stg.cdc_order_header WHERE op = 'D' GROUP BY 1),
nv AS (SELECT order_number, count(*) AS n_versions, count(DISTINCT source_system) AS n_sources,
              count(DISTINCT outlet_code) AS n_outlets
       FROM stg.cdc_order_header WHERE op IN ('I','U') GROUP BY 1)
SELECT l.order_number, l.outlet_code, i.outlet_code_at_insert, l.warehouse_code, l.route_code,
  l.order_date, l.requested_delivery_date, l.order_status, l.line_count,
  l.order_value_gross AS order_value_gross_reported,
  CASE WHEN l.source_system = 'PARTNER_API' THEN round(l.order_value_gross / {{PARTNER_FACTOR}}, 2)
       ELSE l.order_value_gross END AS order_value_gross_adj,
  l.discount_amount, l.tax_amount,
  l.source_system AS source_system_latest, i.source_system_at_insert,
  (d.order_number IS NOT NULL) AS is_deleted, d.deleted_extract_date,
  nv.n_versions, nv.n_sources, nv.n_outlets, i.inserted_at, l.op_ts AS last_change_ts,
  l._src_file, l._src_row
FROM latest l
LEFT JOIN ins i USING (order_number)
LEFT JOIN del d USING (order_number)
LEFT JOIN nv USING (order_number);
