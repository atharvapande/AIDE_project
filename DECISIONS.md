# DECISIONS

**Built.** A DuckDB pipeline (`python -m kestrel build`, about 35 s at scale 1) from raw feeds to marts. Every row keeps
its source file and row; every removed row is in `dq.quarantine` with a reason. A 12-KPI catalogue, nine parameterised
queries, a weekly bridge to the legacy Finance report, and `ask`: the model picks a vetted query or writes one read-only
SELECT, and the interpretation, parameters and SQL are always printed. Evidence is in `profiling/`.

**Not built.** Dashboard, incremental loads, orchestration. No figure for carrier breach, service level or trip breach:
the data cannot support them and the catalogue says so. No forcing of the legacy report to tie.

**Judgement calls (each moves a number).**
1. Gross = qty x unit_price. Pricing per each makes monthly sales jump 3.7x when the POS schema changed (2025-10), and
   the source's own tax is 12% of qty x price on case lines. The per-each figure stays beside it.
2. Channel = outlet channel on the sale date (KP-3155), not the till channel. It moves tens of crores between channels.
3. POS lines before 2025-10 have no unit of measure and are treated as eaches, so eaches are not comparable across it.
4. All reefer readings are treated as chilled. Fahrenheit converted, missing units inferred from vendor, firmware 2.1.4
   clocks corrected by 7 h. Excursion = above 8 C. Corrected rate 7.2%; the "third" was Fahrenheit read as Celsius.
5. A device-day stands in for a trip (LOW confidence): there is no trip id, and 75% of device-days breach.
6. Cycle time = first RECEIVE to last DISPATCH per order and site, capped at 24 h. An order's scans sit on about 4.7
   different days, so under 10 orders per warehouse are measurable. Indicative only.
7. An order delete is terminal (it carries the insert's timestamp, so latest-wins resurrects it). Master deletes are not:
   33 of 48 deleted outlets are updated afterwards.
8. PARTNER_API order values are divided by 1.085 in an adjusted column. The factor is read off the data; no invoices.
9. Legacy weeks end on Wednesday as published; legacy channel assumed to be the till channel.
10. Baskets = distinct (basket_id, outlet, day); basket_id alone spans several outlets for 65% of baskets.

**Contract errors found.** POS has all four channels, not two. `temp_unit` is null on 8% of rows. The clock fault is
not fixed.

**Unresolved.** POS is about INR 370 crore a year, the order header about 5,100, the brief says 900. The legacy report
has no relationship to the feed (weekly correlation -0.04); the bridge explains duplicates (INR 11 crore) and channel,
and leaves INR 97 crore unexplained.

**Two more weeks.** Trip table and delivery timestamps from operations; the legacy script and invoices from Finance to
settle items 1 and 8. Incremental loads with a watermark. Per-gateway freshness monitoring. An evaluation set for `ask`.

**What breaks first.** At scale 1 the heaviest steps are the POS as-of join and the 16-column telemetry dedup window.
Scale 10 is not yet measured. Expected order: (1) the dedup window spills first; (2) file inventory, 12.5k footers now,
about 125k at 10x, and one file-list literal per feed; (3) around 100x the full rebuild into one DuckDB file, which
should become partition-level loads with hash-keyed dedup.

**Where `ask` can still be wrong.** It once read "last quarter" as the wrong fiscal quarter. Guardrails stop unsafe SQL,
not a misreading, so the reader sees the parameters and SQL, and the prompt states the latest complete period.
