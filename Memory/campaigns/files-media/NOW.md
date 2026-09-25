# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 8A done, not yet committed. 8B (owner-only export) is next.

**8A shipped (2026-09-25):** migration `20260925130000_files_media_trash_purge.sql` live on the remote —
`purge_expired_trashed_files()` (30-day sweep), `files.purged_at`/nullable `object_key`, `file_purge_log`
(readable by `files.trash` holders), `restore_file` and `list_files('trash')` updated to exclude a purged
File. Purge never deletes the `files` row — only clears its storage keys — specifically so
`quote_version_attachments`/`quote_version_lines`/`job_report_photos`'s RESTRICT foreign keys are never
touched and every "Photo removed" placeholder a customer already saw keeps showing forever (Jafar approved
this over full-row deletion, 2026-09-25). Worker wiring: `sweepExpiredTrash()` in
`processing-worker.ts`, called from the existing `/api/internal/files/processing-worker` route (no new cron
job — reuses the once-a-minute wake). Defensive `object_key is null` guards added to `/api/files/[id]/view`,
`/download`, and the three public byte-serving routes (`/ci`, `/q/…/files`, `/w/…/files`) — verified those and
`/f/…` (customer share) already gate on `trashed_at is null` first, so a purged File was already unreachable
there; the guards are defense in depth for a direct-by-id fetch.

**Verified:** 21/21 new pgTAP assertions (`files_media_trash_purge.sql`) — bounds, idempotency, multi-tenant,
RLS, and the RESTRICT-survival proof against a real published quote version. Ran against a rolled-back
transaction on the live remote (0 files due for purge yet — nothing in real data is 30 days old). Full local
`supabase test db` shows no new regressions beyond the pre-existing stale set already on record below.
`npm run db:types` regenerated. Prettier clean on all touched `.ts` files. `npm run check` confirmed clean —
only the 3 known-stale "union type too complex" errors remain, zero new ones.

**Not yet done for 8A:** no unit test for `sweepExpiredTrash` (matches the existing gap on its sibling
`sweepAbandonedFileUploads` — not a new regression), no browser check (the worker doesn't run locally; nothing
in Raad's real data is old enough to purge yet regardless). Not yet committed to git.

**Exact next action:** `git commit` the 8A changes (migration, `processing-worker.ts`, the internal route, the
view/download/public-route guards, the pgTAP file, and `database.types.ts`). Then start 8B: an owner-only
"download everything" export (metadata, link manifests, checksums, permitted blobs).

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked".
Test with existing checked photos (Raad LTD has 12).

**Browser note:** the Chrome tab runs hidden, which pauses animation frames, slows timers and never loads
`loading="lazy"` images — drive pages with javascript and read the DOM. Role checks: impersonate in SQL inside a
rolled-back transaction; Raad LTD org `18f0d717-904e-48d8-bd99-9df7e3844cda`.

**Known stale pgTAP (not regressions):** `files_manage_actions.sql` 15–16, 23; `files_media_central_catalog.sql`
16; `files_media_upload_pipeline.sql`. `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192` and has 3
pre-existing "union type too complex" errors. Supabase CLI is `npx supabase`; run SQL files with `npx supabase
db query --linked -f <file>`.
