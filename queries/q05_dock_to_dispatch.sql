-- @param max_hours = 24
-- KPI K07. Dock-to-dispatch hours by warehouse = first RECEIVE scan to last DISPATCH scan for the same order
-- and warehouse. LOW CONFIDENCE: scans of one order are spread over ~4.7 different days and only a small share
-- of orders has both scans at one warehouse. Pairs longer than max_hours are treated as unmatched scans, not as
-- real cycle times. The uncapped median is shown to prove why the cap is needed.
WITH p AS (
  SELECT warehouse_code, order_number, epoch(last_dispatch - first_receive) / 3600.0 AS hrs
  FROM mart.wms_order_warehouse
  WHERE first_receive IS NOT NULL AND last_dispatch IS NOT NULL AND last_dispatch >= first_receive),
t AS (SELECT warehouse_code, count(DISTINCT order_number) AS orders_scanned FROM core.wms_scan GROUP BY 1)
SELECT t.warehouse_code, w.warehouse_name,
  count(p.hrs) FILTER (WHERE p.hrs <= CAST($max_hours AS DOUBLE)) AS orders_measured,
  t.orders_scanned,
  round(100.0 * count(p.hrs) FILTER (WHERE p.hrs <= CAST($max_hours AS DOUBLE)) / t.orders_scanned, 2) AS coverage_pct,
  round(median(p.hrs) FILTER (WHERE p.hrs <= CAST($max_hours AS DOUBLE)), 2) AS median_hours_capped,
  count(p.hrs) AS pairs_uncapped, round(median(p.hrs), 1) AS median_hours_uncapped,
  'LOW' AS confidence
FROM t LEFT JOIN p USING (warehouse_code) LEFT JOIN ref.warehouse_master w USING (warehouse_code)
GROUP BY t.warehouse_code, w.warehouse_name, t.orders_scanned ORDER BY t.warehouse_code;
