CREATE OR REPLACE TABLE stg.reefer_telemetry AS
SELECT
  device_id, telemetry_vendor, firmware_version, vehicle_registration, route_code, warehouse_code,
  gateway_id, CAST(reading_ts AS TIMESTAMP) AS reading_ts_raw, temp_value, temp_unit,
  humidity_pct, door_open_flag, gps_lat, gps_lon, battery_pct, CAST(dt AS DATE) AS dt,
  filename AS _src_file, file_row_number AS _src_row
FROM {{TEL}};
