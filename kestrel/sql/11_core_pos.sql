-- Dedup: the collector is at-least-once. Key is (txn_id, txn_line_no). First arrival wins.
CREATE OR REPLACE TABLE core.pos_ranked AS
SELECT *, row_number() OVER (PARTITION BY txn_id, txn_line_no ORDER BY ingest_date, _src_file, _src_row) AS rn
FROM stg.pos_transactions;

INSERT INTO dq.quarantine
SELECT 'pos_transactions', 'DUPLICATE_LINE', txn_id || '/' || txn_line_no, _src_file, _src_row
FROM core.pos_ranked WHERE rn > 1;

-- Fact. Channel is as-of the sale (outlet SCD2); till channel kept alongside.
-- Eaches: CS rows x eaches_per_case (uom_conversion, falling back to product case_pack).
-- Gross = extended line value before discount, ex tax. GROSS_QTY is set by KESTREL_PRICE_BASIS.
CREATE OR REPLACE TABLE core.pos_sales AS
WITH base AS (SELECT * EXCLUDE (rn) FROM core.pos_ranked WHERE rn = 1),
j AS (
  SELECT b.*, o.channel AS channel_asof, o.version_no AS outlet_version_no,
         u.eaches_per_case AS epc_uom, p.case_pack AS epc_product
  FROM base b
  ASOF LEFT JOIN core.outlet_version o
    ON b.outlet_code = o.outlet_code AND b.event_ts_utc >= o.valid_from
  LEFT JOIN ref.uom_conversion u ON u.sku_code = b.sku_code
  LEFT JOIN core.product_current p ON p.sku_code = b.sku_code
),
k AS (
  SELECT *, COALESCE(epc_uom, epc_product) AS eaches_per_case,
    CASE WHEN epc_uom IS NOT NULL THEN 'uom_conversion' WHEN epc_product IS NOT NULL THEN 'product_master_case_pack' END AS factor_source,
    COALESCE(channel_asof, till_channel) AS channel,
    CASE WHEN uom = 'CS' THEN qty_raw * COALESCE(epc_uom, epc_product) ELSE qty_raw END AS qty_eaches
  FROM j
)
SELECT k.txn_id, k.txn_line_no, k.basket_id, k.outlet_code, k.sku_code,
  k.event_ts_utc, k.event_ts_ist, k.sale_date, k.ingest_date,
  k.channel, k.till_channel, k.outlet_version_no,
  k.uom, k.uom_assumed, k.qty_raw, k.eaches_per_case, k.factor_source, k.qty_eaches,
  k.unit_price,
  round({{GROSS_QTY}} * k.unit_price, 2) AS gross_sales_inr,
  k.discount_amount, k.tax_amount,
  round({{GROSS_QTY}} * k.unit_price - k.discount_amount, 2) AS net_sales_inr,
  k.payment_mode, k.promo_code, k.loyalty_id,
  c.fiscal_year, c.fiscal_quarter, c.fiscal_month_no, c.iso_week,
  (k.ingest_date > k.sale_date) AS arrived_late,
  k._src_file, k._src_row
FROM k LEFT JOIN ref.fiscal_calendar c ON c.calendar_date = k.sale_date;
