-- @param tolerance_pct = 2
-- KPI K09. Order value by source system, and whether the sources are comparable. Deleted orders excluded.
-- source_system changes between versions of the same order, so two bases are shown. Inflation of ~8.5% sits on
-- versions whose source is PARTNER_API, so it is visible on the 'latest' basis, hidden on the 'at_insert' basis.
-- adj = reported / 1.085 for PARTNER_API (assumed freight; no invoice data exists to prove it).
-- mean_vs_typical_pct compares each source's mean reported value with the MIDDLE of the three source means, so one
-- outlying source cannot make the others look off. comparable = within tolerance_pct (default 2%, a judgement).
WITH s AS (
  SELECT 'latest_version' AS basis, source_system_latest AS source_system, count(*) AS orders,
    sum(order_value_gross_reported) AS sum_reported, sum(order_value_gross_adj) AS sum_adj,
    median(order_value_gross_reported) AS median_reported
  FROM mart.order_fact GROUP BY 2
  UNION ALL
  SELECT 'at_insert', source_system_at_insert, count(*), sum(order_value_gross_reported),
    sum(order_value_gross_adj), median(order_value_gross_reported)
  FROM mart.order_fact GROUP BY 2)
SELECT basis, source_system, orders,
  round(sum_reported / orders, 0) AS mean_reported_inr,
  round(median_reported, 0) AS median_reported_inr,
  round(sum_adj / orders, 0) AS mean_adjusted_inr,
  round(sum_reported / 1e7, 2) AS total_reported_crore,
  round(100.0 * ((sum_reported / orders) / median(sum_reported / orders) OVER (PARTITION BY basis) - 1), 2) AS mean_vs_typical_pct,
  CASE WHEN abs(100.0 * ((sum_reported / orders) / median(sum_reported / orders) OVER (PARTITION BY basis) - 1)) <= CAST($tolerance_pct AS DOUBLE)
       THEN 'comparable' ELSE 'NOT comparable' END AS comparable_with_others
FROM s ORDER BY basis, source_system;
