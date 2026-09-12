# Contractor Settings: Current Checkpoint

## Goal

Give contractors one permission-aware control room for business identity and feature-owned settings.

## Where things stand

Part 4B-2a (booking-rule settings foundation) closed 2026-09-13 — see ROADMAP.md.

Part 4B-2b (the availability/slot engine) is done and verified: all 30 pgTAP assertions in
`supabase/tests/database/contractor_settings_booking_availability_engine.sql` pass against the dev database.
Two real bugs were found and fixed while running the test, not just fixture typos:

1. `get_form_available_slots` read `organizations.timezone`, but timezone lives on `organization_settings`
   (fixed in the migration file and re-applied live to dev via `execute_sql`).
2. The test's own min-notice assertion used a date 73 years out (2099-01-05) with an out-of-range
   `min_notice_minutes` (999999999, over the 43200/30-day cap) — even the real 30-day cap can never push
   "now" past a date decades away, so that assertion now targets the nearest real Monday instead.
   Three smaller fixture-only mistakes (wrong column names) were also fixed in the test file.

`src/lib/database.types.ts` has been regenerated and is **not** a no-op this time: the two new `public.*`
functions (`get_form_available_slots`, `claim_form_booking_reservation`) now appear in the Functions section
even though their backing table is in `private`. Prettier-checked clean.

## Next action

Jafar approved the commit 2026-09-13. Parts 4B-2a and 4B-2b are committed. Start Part 4B-2c: the booking-rule
builder screens (rule settings UI + bookable-services picker + live preview showing sample slots), matching
4B-1's builder UX conventions. Load `.claude/skills/design/SKILL.md` and `.claude/skills/svelte/SKILL.md`
before touching any of it — this part is UI, not database.

## Env notes

- Uncommitted right now: `supabase/migrations/20260913160000_contractor_settings_booking_rules_foundation.sql`,
  `supabase/tests/database/contractor_settings_forms_booking_rules_foundation.sql`, the regenerated
  `src/lib/database.types.ts`, plus 4B-2b's `supabase/migrations/20260913170000_contractor_settings_booking_availability_engine.sql`
  (now with the timezone fix) and `supabase/tests/database/contractor_settings_booking_availability_engine.sql`
  (now with the fixture fixes). Ask Jafar before committing (he likes to be asked each time).
- Two deliberate departures from Jobber this part (radius instead of a drawn service area; fixed buffer
  instead of real drive-time) are recorded in `.claude/skills/jobber/jobber-02-requests-leads.md` § 5 —
  read that before designing 4B-2c's buffer/service-area behavior. They still need a one-line mention added to
  `docs/PRODUCT.md` whenever that section is next touched; not done yet.
- Full `npm run check` OOMs — verify TS with a scratch tsconfig that `extends: "./tsconfig.json"` (not
  `.svelte-kit/tsconfig.json` directly) and explicitly includes `.svelte-kit/ambient.d.ts` + `env.d.ts` +
  `non-ambient.d.ts` alongside the target files. Prettier can't glob `(app)` — pass full paths.
- Dev server can crash blank after a restart with "Cannot read properties of undefined (reading 'call')" —
  a mixed `?v=` dep-cache issue. Fix: `rm -rf node_modules/.vite` + hard reload (Ctrl+Shift+R).
- pgTAP tests run against the shared dev database, not an isolated instance: real organizations already carry
  real data. Both booking test files neutralize/scope around other orgs' rows for the length of their own
  rolled-back transaction — copy that pattern for 4B-2c's tests if they touch anything shared/ordered.
- The Supabase MCP `execute_sql` tool only returns the LAST statement's result set from a multi-statement
  query, so a bare pgTAP run only proves the final assertion passed and nothing threw. To see every
  ok/not ok line, wrap assertions as `insert into tap_log(msg) select is(...)` into a temp table (with
  `grant insert on tap_log to authenticated` since role switches mid-transaction need it), then
  `select string_agg(...) from tap_log` as the final statement.

Resume command: `continue contractor settings`.
