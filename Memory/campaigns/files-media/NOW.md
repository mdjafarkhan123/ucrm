# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** Part 4 is complete and committed (`1a84fe1`). Part 5, operational-record adoption, is next
and dependency-ready.

**Exact next action:** Start Part 5 with one record — Client — mounting `FilePicker` in its files area so the
CRM reads and writes the catalog there instead of the old `attachments` path. That is also where the picker
gets its browser pass, and where a record-origin upload should gain its link when the worker publishes it.

**Blockers:**

- An upload still cannot be watched turning usable until deployment sets the values in ROADMAP "Approval
  gates" (worker secret, scanner host/port, two Vault secrets, and the cron job that ships switched off).
  Until then every upload correctly stops at "Still being checked".

**Non-obvious risks:**

- `FilePicker` has no caller until Part 5, so it is proved by `FilePicker.svelte.spec.ts` (5 tests) rather
  than in a browser. Everything else in Part 4 was checked in the real app on 2026-09-21.
- Catalog search is `ilike` with no trigram index (pg_trgm is not installed). Bounded by tenant + page size;
  one of the things Part 8 has to measure.
- `supabase/tests/database/files_media_central_catalog.sql` aborts partway (41 of 49 assertions run, all
  passing) because its backfill assertion re-runs `private.backfill_files_from_attachments` on rows already
  there. Pre-existing.
- `npm run test:unit` currently fails 71 tests across quotes, settings and team. All predate this work and
  none touch Files.

**Pointers:**

- `docs/files-media-behavior-contract.md` — the approved model, including the three reuse decisions
- `Design/Files and Media/README.md` — the workspace blueprint
