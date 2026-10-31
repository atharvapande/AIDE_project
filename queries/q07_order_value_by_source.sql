-- KPI K09. Order value by source system, and whether the sources are comparable. Deleted orders excluded.
-- source_system changes between versions of the same order, so two bases are shown. Inflation of ~8.5% sits on
-- versions whose source is PARTNER_API, so it is visible on the 'latest' basis, hidden on the 'at_insert' basis.
-- adj = reported / 1.085 for PARTNER_API (assumed freight; no invoice data exists to prove it).
SELECT 'latest_version' AS basis, source_system_latest AS source_system, count(*) AS orders,
  round(avg(order_value_gross_reported), 0) AS mean_reported_inr,
  round(median(order_value_gross_reported), 0) AS median_reported_inr,
  round(avg(order_value_gross_adj), 0) AS mean_adjusted_inr,
  round(sum(order_value_gross_reported) / 1e7, 2) AS total_reported_crore
FROM mart.order_fact GROUP BY 2
UNION ALL
SELECT 'at_insert', source_system_at_insert, count(*), round(avg(order_value_gross_reported), 0),
  round(median(order_value_gross_reported), 0), round(avg(order_value_gross_adj), 0),
  round(sum(order_value_gross_reported) / 1e7, 2)
FROM mart.order_fact GROUP BY 2
ORDER BY 1, 2;
