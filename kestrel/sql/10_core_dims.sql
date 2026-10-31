-- Point-in-time (SCD2) outlet and product versions, ordered by (op_ts, seq). NEVER by extract_date.
-- DECISION: deletes do not create a version. They are recorded as deleted_at on the key. Master
-- deletes are followed by further updates for many keys, so a delete is not treated as terminal here.
-- DECISION: two records with the same (key, op_ts): the higher seq wins; the other is quarantined.
CREATE OR REPLACE TABLE core.outlet_ranked AS
SELECT *, row_number() OVER (PARTITION BY outlet_code, op_ts ORDER BY seq DESC) AS rn_tie
FROM stg.cdc_outlet WHERE op IN ('I','U');

INSERT INTO dq.quarantine
SELECT 'erp_outlet_master', 'SAME_OP_TS_SUPERSEDED_BY_HIGHER_SEQ', outlet_code || '@' || op_ts, _src_file, _src_row
FROM core.outlet_ranked WHERE rn_tie > 1;

CREATE OR REPLACE TABLE core.outlet_version AS
SELECT outlet_code,
  op_ts AS valid_from,
  COALESCE(lead(op_ts) OVER (PARTITION BY outlet_code ORDER BY op_ts), TIMESTAMP '9999-12-31') AS valid_to,
  row_number() OVER (PARTITION BY outlet_code ORDER BY op_ts) AS version_no,
  channel,
  lag(channel) OVER (PARTITION BY outlet_code ORDER BY op_ts) AS prev_channel,
  COALESCE(channel IS DISTINCT FROM lag(channel) OVER (PARTITION BY outlet_code ORDER BY op_ts)
           AND lag(channel) OVER (PARTITION BY outlet_code ORDER BY op_ts) IS NOT NULL, false) AS channel_changed,
  outlet_name, outlet_format, city, route_code, warehouse_code, credit_limit, credit_terms_days,
  gst_number, status, seq, _src_file, _src_row
FROM core.outlet_ranked WHERE rn_tie = 1;

CREATE OR REPLACE TABLE core.outlet_current AS
SELECT v.* EXCLUDE (valid_to, prev_channel, channel_changed), d.deleted_at
FROM core.outlet_version v
LEFT JOIN (SELECT outlet_code, max(op_ts) AS deleted_at FROM stg.cdc_outlet WHERE op = 'D' GROUP BY 1) d USING (outlet_code)
QUALIFY row_number() OVER (PARTITION BY v.outlet_code ORDER BY v.valid_from DESC) = 1;

CREATE OR REPLACE TABLE core.product_ranked AS
SELECT *, row_number() OVER (PARTITION BY sku_code, op_ts ORDER BY seq DESC) AS rn_tie
FROM stg.cdc_product WHERE op IN ('I','U');

INSERT INTO dq.quarantine
SELECT 'erp_product_master', 'SAME_OP_TS_SUPERSEDED_BY_HIGHER_SEQ', sku_code || '@' || op_ts, _src_file, _src_row
FROM core.product_ranked WHERE rn_tie > 1;

CREATE OR REPLACE TABLE core.product_version AS
SELECT sku_code, op_ts AS valid_from,
  COALESCE(lead(op_ts) OVER (PARTITION BY sku_code ORDER BY op_ts), TIMESTAMP '9999-12-31') AS valid_to,
  product_name, category, brand, case_pack, mrp, list_price, gst_rate_pct, shelf_life_days, is_chilled,
  status, seq, _src_file, _src_row
FROM core.product_ranked WHERE rn_tie = 1;

CREATE OR REPLACE TABLE core.product_current AS
SELECT v.* EXCLUDE (valid_to), d.deleted_at
FROM core.product_version v
LEFT JOIN (SELECT sku_code, max(op_ts) AS deleted_at FROM stg.cdc_product WHERE op = 'D' GROUP BY 1) d USING (sku_code)
QUALIFY row_number() OVER (PARTITION BY v.sku_code ORDER BY v.valid_from DESC) = 1;
