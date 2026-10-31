-- @param outlet_code = NULL
-- @param from_date = NULL
-- @param to_date = NULL
-- KPI K08. Outlets whose channel classification changed, and when (master op_ts, UTC). Dates are YYYY-MM-DD.
-- A change is a new master version whose channel differs from the previous version.
SELECT outlet_code, changed_at, from_channel, to_channel,
  count(*) OVER (PARTITION BY outlet_code) AS changes_for_outlet
FROM mart.outlet_channel_changes
WHERE (CAST($outlet_code AS VARCHAR) IS NULL OR outlet_code = CAST($outlet_code AS VARCHAR))
  AND (CAST($from_date AS DATE) IS NULL OR changed_at >= CAST($from_date AS DATE))
  AND (CAST($to_date AS DATE) IS NULL OR changed_at < CAST($to_date AS DATE) + INTERVAL 1 DAY)
ORDER BY changed_at, outlet_code;
