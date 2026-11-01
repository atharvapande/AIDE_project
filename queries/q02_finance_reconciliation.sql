-- @param fiscal_year = NULL
-- @param fiscal_quarter = NULL
-- KPI K11. Kestrel gross vs the published Finance weekly report for one fiscal quarter
-- (default: the latest complete quarter, same as q01).
-- Compared on whole legacy weeks whose week_ending falls inside the quarter. Legacy weeks end on Wednesday, so the
-- first week reaches back a few days before the quarter and the last days of the quarter may fall after the last
-- published week. 'weeks' shows how many were compared. q01 gives the exact calendar-quarter figure.
-- Reads left to right: legacy -> rebuilt with the legacy method -> remove duplicates -> move to event date
-- -> move to as-of channel = Kestrel. 'unexplained' is what no rule in the raw data accounts for.
WITH q AS (
  SELECT fiscal_year, fiscal_quarter, start_date, end_date FROM mart.fiscal_quarters
  WHERE (CAST($fiscal_year AS VARCHAR) IS NULL AND CAST($fiscal_quarter AS VARCHAR) IS NULL AND is_complete)
     OR (fiscal_year = CAST($fiscal_year AS VARCHAR) AND fiscal_quarter = CAST($fiscal_quarter AS VARCHAR))
  ORDER BY end_date DESC LIMIT 1),
w AS (
  SELECT b.* FROM mart.finance_bridge b, q
  WHERE b.legacy_gross_inr IS NOT NULL AND b.week_ending BETWEEN q.start_date AND q.end_date)
SELECT (SELECT fiscal_year || ' ' || fiscal_quarter FROM q) AS fiscal_quarter,
  coalesce(channel, 'ALL') AS channel, count(DISTINCT week_ending) AS weeks,
  round(sum(legacy_gross_inr) / 1e7, 2) AS legacy_crore,
  round(sum(rebuilt_legacy_method_inr) / 1e7, 2) AS rebuilt_legacy_method_crore,
  round(sum(unexplained_vs_legacy_inr) / 1e7, 2) AS unexplained_crore,
  round(sum(duplicates_inr) / 1e7, 2) AS duplicates_in_legacy_method_crore,
  round(sum(timing_ingest_vs_event_inr) / 1e7, 2) AS move_to_event_date_crore,
  round(sum(channel_reclass_inr) / 1e7, 2) AS move_to_asof_channel_crore,
  round(sum(kestrel_gross_inr) / 1e7, 2) AS kestrel_crore,
  round(sum(total_gap_inr) / 1e7, 2) AS total_gap_crore
FROM w GROUP BY ROLLUP (channel) ORDER BY channel NULLS LAST;
