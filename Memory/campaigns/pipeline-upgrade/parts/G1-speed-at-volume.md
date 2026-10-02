# G1 — Speed at volume

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` (whole plan)
**Code:** `main`
**Done when:** The measured numbers are written down with the volume they were taken at, and no capacity
claim goes beyond them.

## Steps

- [x] Read the method: `.claude/skills/performance-review/references/verify.md`
- [x] Bring the practice database on this computer (Docker `supabase_db_ucrm`) up to the newest migration
- [x] Write and run the fake-company script `scripts/perf/pipeline-volume-seed.sql`
- [ ] Sanity-check the fake data (see Notes)
- [ ] Measure every Pipeline read, as owner and as the restricted member
- [ ] Measure the bulk changes (owner, Task) at the 50-card cap
- [ ] Fix anything slow (load `supabase-postgres-best-practices` first), then re-measure
- [ ] Write `docs/sales-pipeline-performance-verification.md` in the shape of
      `docs/online-payments-performance-verification.md`, and home the stage G carried notes that G1 answers

## Next

Nothing has been measured yet. Start with the sanity check, then run `EXPLAIN (ANALYZE, BUFFERS)` and plain
timings in the practice database for organization `md5('perf-org:perf-volume')::uuid` (20,179 open cards,
83,000 cards in all) and `md5('perf-org:perf-midsize')::uuid` (2,248 open, 8,300 in all). Call each function
as a signed-in member: inside a transaction, `set local role authenticated` and
`set local request.jwt.claims = '{"sub":"<user id>","role":"authenticated"}'`. Member ids are
`perf_seed.uid(<org id>, 'user', n)`: 1 is the owner; the last one (12 in the big company, 6 in the midsize)
has "see every client" taken away.

Reads to measure: `pipeline_board_page` (each column, the grouped `assessment` column and `all` for the
Table; every sort; owner and date filters; search by name, by phone digits, by Quote number; lead source;
a second page), `pipeline_stage_counts` (plain and with search), `pipeline_lead_sources`,
`pipeline_outcome_page`, `pipeline_outcome_tiles`, `pipeline_outcomes_report`, `pipeline_conversion_report`
(one month and All time), `financial_sales_outcomes_page` and `_summary`.

## Notes

- Run SQL with `docker exec -i supabase_db_ucrm psql -U postgres -d postgres`. The Supabase command is
  `npx --no-install supabase`; there is no global `supabase` or `psql`.
- The practice database holds only the fake companies: 10 organizations, 157,700 cards, 426,921 stage
  events, 101,851 Tasks, 57,000 clients. The script took 9.5 minutes; to rebuild, reset the practice
  database first (it does not delete its own rows).
- Sanity check still owed: the script loads with triggers off and writes each card's stage itself. Turn
  triggers on, run `update opportunities set title = title` on a sample of each kind, and confirm no
  `stage` changes. Also confirm one board page and one report return sensible rows.
- Not in the fake data: quote emails (`communication_delivery_intents`), so the board's "quote email
  failed" lookup finds nothing; notes and call logs. Say so in the write-up, or add emails before measuring
  the Awaiting response column.
- Numbers to beat or confirm, from earlier parts: search about 140 ms per column at 5,000 open cards;
  Table 15–30 ms; Conversion tab All time 400–600 ms at 12,000 cards; the grouped Assessment column sorts
  after reading in the Task order.
