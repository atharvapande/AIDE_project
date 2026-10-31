-- scan_id is unique in the data (asserted in dq), so no dedup is needed.
CREATE OR REPLACE TABLE core.wms_scan AS
SELECT *, dt AS scan_date FROM stg.wms_scan_events;
