CREATE OR REPLACE TABLE stg.cdc_outlet AS
SELECT outlet_code, __op AS op, CAST(__op_ts AS TIMESTAMP) AS op_ts, __seq AS seq,
  CAST(extract_date AS DATE) AS extract_date, outlet_name, channel, outlet_format, city, route_code,
  warehouse_code, credit_limit, credit_terms_days, gst_number, status,
  filename AS _src_file, file_row_number AS _src_row
FROM {{OUT}};

CREATE OR REPLACE TABLE stg.cdc_product AS
SELECT sku_code, __op AS op, CAST(__op_ts AS TIMESTAMP) AS op_ts, __seq AS seq,
  CAST(extract_date AS DATE) AS extract_date, product_name, category, brand, case_pack, mrp, list_price,
  gst_rate_pct, shelf_life_days, is_chilled, status,
  filename AS _src_file, file_row_number AS _src_row
FROM {{PROD}};

CREATE OR REPLACE TABLE stg.cdc_order_header AS
SELECT order_number, __op AS op, CAST(__op_ts AS TIMESTAMP) AS op_ts, __seq AS seq,
  CAST(extract_date AS DATE) AS extract_date, outlet_code, warehouse_code, route_code,
  CAST(order_date AS DATE) AS order_date, CAST(requested_delivery_date AS DATE) AS requested_delivery_date,
  order_status, line_count, order_value_gross, discount_amount, tax_amount, source_system,
  filename AS _src_file, file_row_number AS _src_row
FROM {{SOH}};
