-- KPI K05 and K06, by month.
-- excursion_reading_rate = readings above 8C / valid readings (after unit and clock fixes). The defensible figure.
-- device_day_breach_rate = share of device-days with ANY reading above 8C. A device-day is a stand-in for a trip:
-- there is no trip id, and a device-day spans ~19 readings and many route codes. It is dominated by trip length.
-- Carrier cannot be reported: nothing in telemetry links to carrier_master.
WITH r AS (SELECT month, sum(valid_readings) AS vr, sum(excursion_readings) AS er FROM mart.cold_chain_monthly GROUP BY 1),
d AS (SELECT month, count(*) AS device_days, count(*) FILTER (WHERE any_excursion) AS dd_breach,
        round(avg(distinct_routes), 1) AS avg_routes_per_device_day
      FROM mart.cold_chain_device_day WHERE valid_readings > 0 GROUP BY 1)
SELECT r.month, r.vr AS valid_readings, r.er AS excursion_readings,
  round(100.0 * r.er / r.vr, 2) AS excursion_reading_rate_pct,
  d.device_days, d.dd_breach AS device_days_breached,
  round(100.0 * d.dd_breach / d.device_days, 1) AS device_day_breach_rate_pct, d.avg_routes_per_device_day
FROM r JOIN d USING (month) ORDER BY r.month;
