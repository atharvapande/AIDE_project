-- KPI K10. Service level (on-time delivery) is NOT computable from this data. The order header never reaches
-- DELIVERED and there is no delivery timestamp anywhere. This query is the evidence.
SELECT order_status, count(*) AS orders, round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct,
  (order_status = 'DELIVERED') AS delivery_confirmed
FROM mart.order_fact GROUP BY 1 ORDER BY 1;
