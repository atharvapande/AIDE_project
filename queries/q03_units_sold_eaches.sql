-- @param month = NULL
-- KPI K03. Units sold in EACHES for a calendar month (YYYY-MM). Default = last complete month in the data.
-- Case (CS) lines are multiplied by eaches per case. Months before 2025-10 have no uom on the source,
-- so they are counted as captured (assumed eaches) and are NOT comparable with later months.
WITH m AS (
  SELECT CASE WHEN max(sale_date) = last_day(max(sale_date)) THEN strftime(max(sale_date), '%Y-%m')
              ELSE strftime(max(sale_date) - INTERVAL 1 MONTH, '%Y-%m') END AS mo FROM core.pos_sales)
SELECT strftime(sale_date, '%Y-%m') AS month,
  sum(qty_eaches) AS units_eaches,
  sum(qty_raw) AS units_as_captured,
  count(*) FILTER (WHERE uom = 'CS') AS case_lines,
  count(*) AS lines,
  bool_and(NOT uom_assumed) AS uom_known_for_all_lines
FROM core.pos_sales
WHERE strftime(sale_date, '%Y-%m') = coalesce(CAST($month AS VARCHAR), (SELECT mo FROM m))
GROUP BY 1;
