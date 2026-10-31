-- Staging: typed, renamed, lineage attached. No rows dropped here.
-- DECISION: pre-drift files have no uom column; those rows are assumed EA (uom_assumed = true).
-- DECISION: event_ts is UTC (suffix Z). Business day is Asia/Kolkata = UTC + 330 min.
CREATE OR REPLACE TABLE stg.pos_transactions AS
SELECT
  txn_id, txn_line_no, basket_id, outlet_code,
  channel AS till_channel, sku_code,
  CAST(event_ts AS TIMESTAMP) AS event_ts_utc,
  CAST(event_ts AS TIMESTAMP) + INTERVAL ({{IST_MIN}}) MINUTE AS event_ts_ist,
  CAST(CAST(event_ts AS TIMESTAMP) + INTERVAL ({{IST_MIN}}) MINUTE AS DATE) AS sale_date,
  COALESCE(qty, quantity_units) AS qty_raw,
  COALESCE(uom, 'EA') AS uom,
  (uom IS NULL) AS uom_assumed,
  unit_price, discount_amount, tax_amount, payment_mode, till_id, cashier_id,
  promo_code, loyalty_id, CAST(ingest_date AS DATE) AS ingest_date, source_file,
  filename AS _src_file, file_row_number AS _src_row
FROM {{POS}};
