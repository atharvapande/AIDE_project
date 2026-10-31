-- Dedup on every business column (exact duplicates only; at-least-once delivery).
CREATE OR REPLACE TABLE core.telemetry_ranked AS
SELECT *, row_number() OVER (
  PARTITION BY device_id, telemetry_vendor, firmware_version, vehicle_registration, route_code,
    warehouse_code, gateway_id, reading_ts_raw, temp_value, temp_unit, humidity_pct, door_open_flag,
    gps_lat, gps_lon, battery_pct, dt
  ORDER BY _src_file, _src_row) AS rn
FROM stg.reefer_telemetry;

INSERT INTO dq.quarantine
SELECT 'reefer_telemetry', 'DUPLICATE_READING', device_id || '@' || reading_ts_raw, _src_file, _src_row
FROM core.telemetry_ranked WHERE rn > 1;

-- DECISIONS:
--  * unit = temp_unit, else inferred from vendor (COLDEYE = F, THERMLOG = C). Conflicts are asserted in dq.
--  * clock: firmware {{SKEW_FW}} runs +{{SKEW_HOURS}}h; corrected ts = raw - {{SKEW_HOURS}}h.
--  * reading_date = dt partition (verified equal to corrected ts date for every row).
--  * Every reefer reading is treated as chilled (no chilled flag exists in telemetry).
--  * excursion = temp_c > {{TEMP_HI}} (contract: above the band). below_band is kept separately.
CREATE OR REPLACE TABLE core.telemetry_reading AS
WITH x AS (
  SELECT * EXCLUDE (rn),
    COALESCE(temp_unit, CASE WHEN telemetry_vendor = 'COLDEYE' THEN 'F' ELSE 'C' END) AS unit_effective,
    temp_unit IS NULL AS unit_inferred,
    CASE WHEN firmware_version = '{{SKEW_FW}}' THEN reading_ts_raw - INTERVAL ({{SKEW_HOURS}}) HOUR ELSE reading_ts_raw END AS reading_ts
  FROM core.telemetry_ranked WHERE rn = 1
)
SELECT device_id, telemetry_vendor, firmware_version, vehicle_registration, route_code, warehouse_code,
  gateway_id, reading_ts_raw, reading_ts, dt AS reading_date, unit_effective, unit_inferred,
  temp_value,
  CASE WHEN temp_value IS NULL THEN NULL
       WHEN unit_effective = 'F' THEN round((temp_value - 32) * 5.0 / 9, 2) ELSE temp_value END AS temp_c,
  humidity_pct, door_open_flag, gps_lat, gps_lon, battery_pct,
  (firmware_version = '{{SKEW_FW}}') AS clock_corrected,
  _src_file, _src_row
FROM x;

ALTER TABLE core.telemetry_reading ADD COLUMN is_excursion BOOLEAN;
ALTER TABLE core.telemetry_reading ADD COLUMN is_below_band BOOLEAN;
UPDATE core.telemetry_reading SET is_excursion = temp_c > {{TEMP_HI}}, is_below_band = temp_c < {{TEMP_LO}} WHERE temp_c IS NOT NULL;
