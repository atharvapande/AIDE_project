-- 1. Manifest reconciliation. Which partitions are missing, unreadable, or short vs what ingestion says it wrote.
CREATE OR REPLACE TABLE dq.manifest_recon AS
WITH found AS (
  SELECT feed, partition, count(*) AS found_files, count(*) FILTER (WHERE status = 'OK') AS readable_files,
         COALESCE(sum(rows) FILTER (WHERE status = 'OK'), 0) AS readable_rows
  FROM raw.file_inventory GROUP BY 1, 2
),
m AS (SELECT feed, partition, file_count, row_count, bytes FROM read_csv('{{DATA}}/_manifest/expected_partitions.csv'))
SELECT COALESCE(m.feed, f.feed) AS feed, COALESCE(m.partition, f.partition) AS partition,
  m.file_count AS expected_files, m.row_count AS expected_rows,
  COALESCE(f.found_files, 0) AS found_files, COALESCE(f.readable_files, 0) AS readable_files,
  COALESCE(f.readable_rows, 0) AS readable_rows,
  m.row_count - COALESCE(f.readable_rows, 0) AS missing_rows,
  CASE WHEN m.feed IS NULL THEN 'NOT_IN_MANIFEST'
       WHEN f.feed IS NULL THEN 'PARTITION_MISSING'
       WHEN f.readable_files < f.found_files THEN 'UNREADABLE_FILE'
       WHEN m.row_count <> f.readable_rows THEN 'ROW_MISMATCH'
       ELSE 'OK' END AS status
FROM m FULL OUTER JOIN found f ON m.feed = f.feed AND m.partition = f.partition
WHERE COALESCE(m.feed, f.feed) IN (SELECT feed FROM m) OR m.feed IS NOT NULL;

-- 2. Missing days. A day is flagged if a feed has no rows, or fewer than half its trailing 28-day average.
-- This is how we know without being told: expected volume is learned from the data itself.
CREATE OR REPLACE TABLE dq.daily_counts AS
WITH spine AS (SELECT CAST(calendar_date AS DATE) AS d FROM ref.fiscal_calendar),
feeds AS (SELECT unnest(['pos_transactions','reefer_telemetry','wms_scan_events','sales_order_header']) AS feed),
c AS (
  SELECT 'pos_transactions' AS feed, sale_date AS d, count(*) AS rows FROM core.pos_sales GROUP BY 2
  UNION ALL SELECT 'reefer_telemetry', reading_date, count(*) FROM core.telemetry_reading GROUP BY 2
  UNION ALL SELECT 'wms_scan_events', scan_date, count(*) FROM core.wms_scan GROUP BY 2
  UNION ALL SELECT 'sales_order_header', order_date, count(*) FROM core.sales_order GROUP BY 2
)
SELECT f.feed, s.d, COALESCE(c.rows, 0) AS rows
FROM feeds f CROSS JOIN spine s LEFT JOIN c ON c.feed = f.feed AND c.d = s.d;

CREATE OR REPLACE TABLE dq.missing_days AS
SELECT * FROM (
  SELECT feed, d, rows,
    avg(rows) OVER (PARTITION BY feed ORDER BY d ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING) AS trailing_avg
  FROM dq.daily_counts
) WHERE rows = 0 OR (trailing_avg IS NOT NULL AND rows < 0.5 * trailing_avg);

-- 3. Gateway outages hide at gateway x day grain: the feed total barely moves when one of 39 gateways goes quiet.
CREATE OR REPLACE TABLE dq.gateway_day_gaps AS
WITH g AS (SELECT DISTINCT gateway_id FROM core.telemetry_reading),
spine AS (SELECT CAST(calendar_date AS DATE) AS d FROM ref.fiscal_calendar),
c AS (SELECT gateway_id, reading_date AS d, count(*) AS rows FROM core.telemetry_reading GROUP BY 1, 2)
SELECT g.gateway_id, s.d AS missing_date
FROM g CROSS JOIN spine s LEFT JOIN c ON c.gateway_id = g.gateway_id AND c.d = s.d
WHERE c.rows IS NULL;

-- 4. Row accounting: every staged row is either in core or quarantined with a reason.
CREATE OR REPLACE TABLE dq.row_accounting AS
SELECT 'pos_transactions' AS feed, (SELECT count(*) FROM stg.pos_transactions) AS rows_staged,
  (SELECT count(*) FROM core.pos_sales) AS rows_core,
  (SELECT count(*) FROM dq.quarantine WHERE feed = 'pos_transactions') AS rows_quarantined
UNION ALL SELECT 'reefer_telemetry', (SELECT count(*) FROM stg.reefer_telemetry),
  (SELECT count(*) FROM core.telemetry_reading), (SELECT count(*) FROM dq.quarantine WHERE feed = 'reefer_telemetry')
UNION ALL SELECT 'wms_scan_events', (SELECT count(*) FROM stg.wms_scan_events),
  (SELECT count(*) FROM core.wms_scan), 0
UNION ALL SELECT 'erp_outlet_master', (SELECT count(*) FROM stg.cdc_outlet WHERE op IN ('I','U')),
  (SELECT count(*) FROM core.outlet_version), (SELECT count(*) FROM dq.quarantine WHERE feed = 'erp_outlet_master')
UNION ALL SELECT 'erp_product_master', (SELECT count(*) FROM stg.cdc_product WHERE op IN ('I','U')),
  (SELECT count(*) FROM core.product_version), (SELECT count(*) FROM dq.quarantine WHERE feed = 'erp_product_master');

-- 5. Assertions. FAIL on severity ERROR means the build should not be trusted; INFO documents a known data property.
CREATE OR REPLACE TABLE dq.assertions (check_name VARCHAR, severity VARCHAR, expected VARCHAR, actual VARCHAR, passed BOOLEAN);

INSERT INTO dq.assertions
SELECT 'row_conservation_' || feed, 'ERROR', '0', CAST(rows_staged - rows_core - rows_quarantined AS VARCHAR),
  rows_staged - rows_core - rows_quarantined = 0 FROM dq.row_accounting;

INSERT INTO dq.assertions
SELECT 'staged_rows_equal_readable_manifest_rows_' || feed, 'ERROR', '0',
  CAST(sum(readable_rows) - CASE feed WHEN 'pos_transactions' THEN (SELECT count(*) FROM stg.pos_transactions)
    WHEN 'reefer_telemetry' THEN (SELECT count(*) FROM stg.reefer_telemetry)
    ELSE (SELECT count(*) FROM stg.wms_scan_events) END AS VARCHAR),
  sum(readable_rows) - CASE feed WHEN 'pos_transactions' THEN (SELECT count(*) FROM stg.pos_transactions)
    WHEN 'reefer_telemetry' THEN (SELECT count(*) FROM stg.reefer_telemetry)
    ELSE (SELECT count(*) FROM stg.wms_scan_events) END = 0
FROM dq.manifest_recon WHERE feed IN ('pos_transactions','reefer_telemetry','wms_scan_events') GROUP BY feed;

INSERT INTO dq.assertions
SELECT 'manifest_rows_missing_' || feed, 'WARN', '0', CAST(sum(missing_rows) AS VARCHAR), sum(missing_rows) = 0
FROM dq.manifest_recon WHERE feed IN ('pos_transactions','reefer_telemetry','wms_scan_events') GROUP BY feed;

INSERT INTO dq.assertions
SELECT 'unreadable_files', 'WARN', '0', CAST(count(*) AS VARCHAR), count(*) = 0 FROM raw.file_inventory WHERE status <> 'OK';

INSERT INTO dq.assertions
SELECT 'telemetry_unit_conflicts_vendor', 'ERROR', '0', CAST(count(*) AS VARCHAR), count(*) = 0
FROM stg.reefer_telemetry
WHERE temp_unit IS NOT NULL AND temp_unit <> CASE WHEN telemetry_vendor = 'COLDEYE' THEN 'F' ELSE 'C' END;

INSERT INTO dq.assertions
SELECT 'telemetry_corrected_date_equals_dt', 'ERROR', '0 mismatches', CAST(count(*) AS VARCHAR), count(*) = 0
FROM core.telemetry_reading WHERE CAST(reading_ts AS DATE) <> reading_date;

INSERT INTO dq.assertions
SELECT 'telemetry_raw_date_differs_from_dt_without_correction', 'INFO', '>0 (proves skew exists)', CAST(count(*) AS VARCHAR), count(*) > 0
FROM core.telemetry_reading WHERE CAST(reading_ts_raw AS DATE) <> reading_date;

INSERT INTO dq.assertions
SELECT 'pos_outlets_missing_from_master', 'ERROR', '0', CAST(count(DISTINCT outlet_code) AS VARCHAR), count(*) = 0
FROM core.pos_sales WHERE outlet_version_no IS NULL;

INSERT INTO dq.assertions
SELECT 'pos_skus_missing_from_product_master', 'ERROR', '0', CAST(count(DISTINCT sku_code) AS VARCHAR), count(*) = 0
FROM core.pos_sales WHERE sku_code NOT IN (SELECT sku_code FROM core.product_current);

INSERT INTO dq.assertions
SELECT 'case_rows_without_eaches_factor', 'ERROR', '0', CAST(count(*) AS VARCHAR), count(*) = 0
FROM core.pos_sales WHERE uom = 'CS' AND eaches_per_case IS NULL;

INSERT INTO dq.assertions
SELECT 'skus_missing_from_uom_conversion_table', 'INFO', 'known gap, covered by product case_pack', CAST(count(*) AS VARCHAR), true
FROM core.product_current WHERE sku_code NOT IN (SELECT sku_code FROM ref.uom_conversion);

INSERT INTO dq.assertions
SELECT 'wms_scan_id_unique', 'ERROR', '0 duplicates', CAST(count(*) - count(DISTINCT scan_id) AS VARCHAR),
  count(*) = count(DISTINCT scan_id) FROM core.wms_scan;

INSERT INTO dq.assertions
SELECT 'wms_orders_not_in_order_header', 'WARN', '0', CAST(count(DISTINCT order_number) AS VARCHAR), count(*) = 0
FROM core.wms_scan WHERE order_number NOT IN (SELECT order_number FROM core.sales_order);

INSERT INTO dq.assertions
SELECT 'orders_deleted', 'INFO', 'excluded from marts', CAST(count(*) AS VARCHAR), true FROM core.sales_order WHERE is_deleted;

INSERT INTO dq.assertions
SELECT 'orders_with_changing_source_system', 'INFO', 'source_system unstable per order', CAST(count(*) AS VARCHAR), true
FROM core.sales_order WHERE n_sources > 1;

INSERT INTO dq.assertions
SELECT 'orders_with_changing_outlet_code', 'INFO', 'outlet unstable per order', CAST(count(*) AS VARCHAR), true
FROM core.sales_order WHERE n_outlets > 1;

INSERT INTO dq.assertions
SELECT 'pos_late_arrival_share', 'INFO', '~4.5% in shipped data', CAST(round(avg(arrived_late::INT), 4) AS VARCHAR), true FROM core.pos_sales;

INSERT INTO dq.assertions
SELECT 'pos_utc_date_differs_from_ist_date_rows', 'INFO', '0 in shipped data (no impact)', CAST(count(*) AS VARCHAR), true
FROM core.pos_sales WHERE CAST(event_ts_utc AS DATE) <> sale_date;

INSERT INTO dq.assertions
SELECT 'pos_pre_drift_rows_assumed_EA', 'INFO', 'uom absent before 2025-10-01', CAST(count(*) AS VARCHAR), true FROM core.pos_sales WHERE uom_assumed;

INSERT INTO dq.assertions
SELECT 'gateway_day_gaps', 'WARN', '0', CAST(count(*) AS VARCHAR), count(*) = 0 FROM dq.gateway_day_gaps;

INSERT INTO dq.assertions
SELECT 'feed_days_missing_or_low', 'WARN', '0', CAST(count(*) AS VARCHAR), count(*) = 0 FROM dq.missing_days;
