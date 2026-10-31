-- KPI K11. Kestrel gross vs the published Finance weekly report, over the weeks the report covers.
-- Reads left to right: legacy -> rebuilt with the legacy method -> remove duplicates -> move to event date
-- -> move to as-of channel = Kestrel. 'unexplained' is what no rule in the raw data accounts for.
SELECT coalesce(channel, 'ALL') AS channel,
  round(sum(legacy_gross_inr) / 1e7, 2) AS legacy_crore,
  round(sum(rebuilt_legacy_method_inr) / 1e7, 2) AS rebuilt_legacy_method_crore,
  round(sum(unexplained_vs_legacy_inr) / 1e7, 2) AS unexplained_crore,
  round(sum(duplicates_inr) / 1e7, 2) AS duplicates_in_legacy_method_crore,
  round(sum(timing_ingest_vs_event_inr) / 1e7, 2) AS move_to_event_date_crore,
  round(sum(channel_reclass_inr) / 1e7, 2) AS move_to_asof_channel_crore,
  round(sum(kestrel_gross_inr) / 1e7, 2) AS kestrel_crore,
  round(sum(total_gap_inr) / 1e7, 2) AS total_gap_crore
FROM mart.finance_bridge WHERE legacy_gross_inr IS NOT NULL
GROUP BY ROLLUP (channel) ORDER BY channel NULLS LAST;
