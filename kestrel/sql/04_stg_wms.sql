-- event_ts is site local. warehouse_master gives Asia/Kolkata for all sites, so no conversion.
CREATE OR REPLACE TABLE stg.wms_scan_events AS
SELECT
  scan_id, warehouse_code, event_type, order_number, sku_code, batch_id, qty_cases, pallet_id,
  dock_door, operator_id, handheld_device, CAST(event_ts AS TIMESTAMP) AS event_ts_local,
  CAST(dt AS DATE) AS dt, filename AS _src_file, file_row_number AS _src_row
FROM {{WMS}};
