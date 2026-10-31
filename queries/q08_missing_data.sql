-- KPI K12. Everything that is missing, found without being told: unreadable files, partitions short of the
-- manifest, feed-days that are empty or under half the trailing 28-day average, and gateway-days with no rows.
SELECT 'unreadable_file' AS kind, feed AS subject, regexp_extract(file, '[^/]+/[^/]+$') AS period,
  NULL::BIGINT AS rows_found, NULL::BIGINT AS rows_expected
FROM raw.file_inventory WHERE status <> 'OK'
UNION ALL
SELECT 'manifest_' || lower(status), feed, partition, readable_rows, expected_rows
FROM dq.manifest_recon WHERE status <> 'OK'
UNION ALL
SELECT 'feed_day_low_or_empty', feed, CAST(d AS VARCHAR), rows, CAST(round(trailing_avg) AS BIGINT) FROM dq.missing_days
UNION ALL
SELECT 'gateway_day_empty', gateway_id, CAST(missing_date AS VARCHAR), 0, NULL FROM dq.gateway_day_gaps
ORDER BY 1, 2, 3;
