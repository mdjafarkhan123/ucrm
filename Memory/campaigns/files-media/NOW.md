# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** Part 4 is built in full. Its last slice — reuse — is `20260921220000` (`attach_file_to_record`
plus `list_files`'s `on_record` / `attachable` arguments), `POST /api/files/links`, `FilePicker.svelte` and
`FileAttachToRecordDialog.svelte` wired into the details panel's "Attach to…". Nothing in Part 4 is committed
yet.

**Exact next action:** Commit Part 4 (read slice, write slice, reuse slice) as one change, then open Part 5,
whose first job is a record editor that mounts `FilePicker` — that is also where the picker gets its browser
pass and where a record-origin upload should gain its link on publish.

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
