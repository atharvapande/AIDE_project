-- @param channel = NULL
-- KPI K11, week by week. Optional channel filter (GT, MT, HORECA, ECOM).
SELECT week_ending, channel, round(legacy_gross_inr, 0) AS legacy_inr, rebuilt_legacy_method_inr,
  duplicates_inr, timing_ingest_vs_event_inr, channel_reclass_inr, kestrel_gross_inr,
  unexplained_vs_legacy_inr, total_gap_inr
FROM mart.finance_bridge
WHERE CAST($channel AS VARCHAR) IS NULL OR channel = CAST($channel AS VARCHAR)
ORDER BY week_ending, channel;
