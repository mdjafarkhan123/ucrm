# G1 — Speed at volume

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` (whole plan)
**Code:** `main`
**Done when:** The measured numbers are written down with the volume they were taken at, and no capacity
claim goes beyond them.

## Steps

- [x] Read the method: `.claude/skills/performance-review/references/verify.md`
- [x] Bring the practice database on this computer (Docker `supabase_db_ucrm`) up to the newest migration
- [x] Write and run the fake-company script `scripts/perf/pipeline-volume-seed.sql`
- [x] Sanity-check the fake data
- [x] Measure every Pipeline read, as owner and as the restricted member
- [x] Measure the bulk changes (owner, Task) at the 50-card cap
- [x] Fix anything slow, then re-measure (migration `20261006100000_pipeline_speed_at_volume.sql`,
      proven in the practice database: same answers as before for 282 calls, three members, two companies)
- [ ] Put the fix on the live database
- [ ] Write `docs/sales-pipeline-performance-verification.md` in the shape of
      `docs/online-payments-performance-verification.md`, and home the stage G carried notes that G1 answers

## Next

Push migration `20261006100000` to the live database with `npx --no-install supabase db push --linked`
(dry run first). Outcome check: `select max(version) from supabase_migrations.schema_migrations` on the live
database reads `20261006100000`; if it already does, do not push again. Then write the verification document
from the timings (re-run `scripts/perf/pipeline-volume-bench.py` if they are needed again).

## Notes

- Run SQL with `docker exec -i supabase_db_ucrm psql -U postgres -d postgres`. The Supabase command is
  `npx --no-install supabase`; there is no global `supabase` or `psql`.
- The practice database holds only the fake companies: 10 organizations, 157,700 cards, 426,921 stage
  events, 101,851 Tasks, 57,000 clients. The script took 9.5 minutes; to rebuild, reset the practice
  database first (it does not delete its own rows).
- Not in the fake data: quote emails (`communication_delivery_intents`), so the board's "quote email
  failed" lookup finds nothing; notes and call logs. Say so in the write-up, or add emails before measuring
  the Awaiting response column.
- Numbers to beat or confirm, from earlier parts: search about 140 ms per column at 5,000 open cards;
  Table 15–30 ms; Conversion tab All time 400–600 ms at 12,000 cards; the grouped Assessment column sorts
  after reading in the Task order.
