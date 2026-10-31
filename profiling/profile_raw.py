import duckdb, glob, os
con = duckdb.connect()
q = lambda s: con.sql(s).fetchall()
def show(t, s):
    print("\n##", t)
    try:
        for r in q(s): print("  ", r)
    except Exception as e: print("  ERR", str(e)[:200])

# corrupt files
bad=[]
for f in glob.glob('data/raw/*/*/*.parquet')+glob.glob('data/raw/erp_cdc/*/*/*.parquet'):
    try: con.sql(f"select count(*) from read_parquet('{f}')").fetchall()
    except Exception as e: bad.append(f)
print("corrupt files:", bad)

P="read_parquet('data/raw/pos_transactions/*/*.parquet', union_by_name=true, hive_partitioning=true, filename=true)"
show("whole POS read & schema cols", f"select count(*), count(qty), count(quantity_units), count(uom) from {P}")
show("POS dup rate (exact on key)", f"select count(*), count(distinct (txn_id,txn_line_no)) from {P}")
show("POS channels", f"select channel,count(*) from {P} group by 1 order by 1")
show("POS UTC vs IST date differ?", f"select count(*) filter (where cast(event_ts::timestamp as date) <> cast((event_ts::timestamp + interval 330 minute) as date)), count(*) from {P}")
show("POS event hour UTC range", f"select min(hour(event_ts::timestamp)),max(hour(event_ts::timestamp)) from {P}")
show("POS ingest!=event(IST) share", f"select avg((ingest_date::date <> cast((event_ts::timestamp + interval 330 minute) as date))::int) from {P}")
show("POS post-drift CS share", f"select uom,count(*) from {P} where quantity_units is not null group by 1")

T="read_parquet('data/raw/reefer_telemetry/*/*.parquet', union_by_name=true, hive_partitioning=true)"
good=[f for f in glob.glob('data/raw/reefer_telemetry/*/*.parquet') if f not in bad]
T="read_parquet(%r, union_by_name=true, hive_partitioning=true)" % good
show("TEL vendor/unit", f"select telemetry_vendor,temp_unit,count(*),round(avg(temp_value),1) from {T} group by 1,2 order by 1,2")
show("TEL skew: reading date != dt", f"select firmware_version, count(*), sum((reading_ts::timestamp::date <> dt::date)::int) from {T} group by 1 order by 1")
show("TEL naive excursion >8 raw vs fixed", f"""select avg((temp_value>8)::int) raw,
 avg(((case when telemetry_vendor='COLDEYE' then (temp_value-32)*5/9 else temp_value end)>8)::int) fixed from {T} where temp_value is not null""")
show("TEL GW-017 daily", f"select dt,count(*) from {T} where gateway_id='GW-017' and dt between '2026-02-09' and '2026-02-14' group by 1 order by 1")
show("TEL dup rate", f"select count(*), (select count(*) from (select distinct * from {T})) from {T}")

W="read_parquet('data/raw/wms_scan_events/*/*.parquet', union_by_name=true, hive_partitioning=true)"
show("WMS rows, orders, scans per order", f"select count(*), count(distinct order_number), round(count(*)*1.0/count(distinct order_number),2) from {W}")
show("WMS orders w/ both PICK & DISPATCH same wh", f"""select count(*) from (select order_number from {W} group by 1 having count(distinct warehouse_code)=1 and bool_or(event_type='PICK') and bool_or(event_type='DISPATCH'))""")
show("WMS dt vs event_ts date", f"select avg((event_ts::timestamp::date<>dt::date)::int) from {W}")

S="read_parquet('data/raw/erp_cdc/sales_order_header/*/*.parquet', union_by_name=true, hive_partitioning=true)"
show("SOH ops", f"select __op,count(*) from {S} group by 1")
show("SOH deleted orders with later-op_ts updates", f"""with d as (select order_number from {S} where __op='D')
select count(*), count(*) filter (where exists(select 1 from {S} s where s.order_number=d.order_number and s.__op='U')) from d""")
show("SOH source_system changes within order", f"select count(*) from (select order_number from {S} where __op<>'D' group by 1 having count(distinct source_system)>1)")
show("SOH avg value by source", f"select source_system,round(avg(order_value_gross)) from {S} where __op<>'D' group by 1")

O="read_parquet('data/raw/erp_cdc/outlet_master/*/*.parquet', union_by_name=true, hive_partitioning=true)"
show("Outlet ops + channel-changing outlets", f"select (select count(*) from {O}), (select count(*) from (select outlet_code from {O} group by 1 having count(distinct channel)>1))")
show("POS till channel vs outlet insert channel mismatch", f"""select avg((p.channel<>o.channel)::int) from (select distinct outlet_code, channel from {P}) p join (select outlet_code, channel from {O} where __op='I') o using(outlet_code)""")

U="read_csv('data/reference/uom_conversion.csv')"
show("UOM coverage", f"select (select count(*) from {U}), (select count(distinct sku_code) from {P})")
show("Legacy report", "select count(*), min(week_ending), max(week_ending), sum(gross_sales_inr) from read_csv('data/reference/legacy_finance_weekly_report.csv')")
show("POS gross (qty*price) total, dedup", f"select round(sum(coalesce(qty,quantity_units)*unit_price)) from (select distinct * exclude(filename, ingest_date) from {P})")
show("Manifest rows vs files", "select feed,sum(row_count) from read_csv('data/_manifest/expected_partitions.csv') group by 1")
