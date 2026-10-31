-- @param month = NULL
-- KPI K05 by warehouse (reading level). Optional month YYYY-MM; default = all months.
SELECT c.warehouse_code, w.warehouse_name, sum(c.valid_readings) AS valid_readings,
  sum(c.excursion_readings) AS excursion_readings,
  round(100.0 * sum(c.excursion_readings) / sum(c.valid_readings), 2) AS excursion_reading_rate_pct
FROM mart.cold_chain_monthly c LEFT JOIN ref.warehouse_master w USING (warehouse_code)
WHERE CAST($month AS VARCHAR) IS NULL OR c.month = CAST($month AS VARCHAR)
GROUP BY 1, 2 ORDER BY 1;
