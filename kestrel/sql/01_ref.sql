-- Reference tables, loaded as-is.
CREATE OR REPLACE TABLE ref.uom_conversion AS SELECT * FROM read_csv('{{DATA}}/reference/uom_conversion.csv');
CREATE OR REPLACE TABLE ref.warehouse_master AS SELECT * FROM read_csv('{{DATA}}/reference/warehouse_master.csv');
CREATE OR REPLACE TABLE ref.carrier_master AS SELECT * FROM read_csv('{{DATA}}/reference/carrier_master.csv');
CREATE OR REPLACE TABLE ref.fiscal_calendar AS SELECT * FROM read_csv('{{DATA}}/reference/fiscal_calendar.csv');
CREATE OR REPLACE TABLE ref.legacy_finance_weekly AS SELECT * FROM read_csv('{{DATA}}/reference/legacy_finance_weekly_report.csv');
CREATE OR REPLACE TABLE dq.quarantine (feed VARCHAR, reason VARCHAR, entity_key VARCHAR, src_file VARCHAR, src_row BIGINT);
