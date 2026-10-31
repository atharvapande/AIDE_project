-- @param fiscal_year = NULL
-- @param fiscal_quarter = NULL
-- KPI K01/K02. Gross and net sales by channel for one fiscal quarter (FY runs Apr-Mar).
-- Default (both params NULL) = the most recent COMPLETE fiscal quarter in the data.
-- Channel = outlet channel as of the sale (point-in-time), not the till channel.
WITH q AS (
  SELECT fiscal_year, fiscal_quarter FROM mart.fiscal_quarters
  WHERE (CAST($fiscal_year AS VARCHAR) IS NULL AND CAST($fiscal_quarter AS VARCHAR) IS NULL AND is_complete)
     OR (fiscal_year = CAST($fiscal_year AS VARCHAR) AND fiscal_quarter = CAST($fiscal_quarter AS VARCHAR))
  ORDER BY end_date DESC LIMIT 1)
SELECT q.fiscal_year, q.fiscal_quarter, coalesce(s.channel, 'ALL') AS channel,
  round(sum(s.gross_sales_inr), 2) AS gross_sales_inr,
  round(sum(s.gross_sales_inr) / 1e7, 2) AS gross_sales_crore,
  round(sum(s.net_sales_inr) / 1e7, 2) AS net_sales_crore,
  sum(s.lines) AS lines
FROM mart.sales_daily_channel s JOIN q USING (fiscal_year, fiscal_quarter)
GROUP BY ROLLUP (q.fiscal_year, q.fiscal_quarter, s.channel)
HAVING q.fiscal_year IS NOT NULL AND q.fiscal_quarter IS NOT NULL
ORDER BY s.channel NULLS LAST;
