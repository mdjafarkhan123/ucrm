# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 8B, backend done and committed; frontend not started. Design fully recorded in
`parts/8B.md` (read it before touching this part again — permission model, cron split, manifest shape,
scope decisions, and why each choice was made).

**8B backend shipped (2026-09-25):** migrations `20260925140000` + fix `20260925141500` live on the remote
— `files.export` permission (owner-only, unlike `files.manage`'s wider spread), `organization_exports`
table + RLS, RPCs (`request_organization_export`, `claim_next_organization_export`,
`finalize_organization_export`, `purge_expired_organization_exports`), and its own cron
(`files-export-worker-wake-five-minutes`, ships switched off like every other worker cron). Worker
(`src/lib/server/files/organization-export.ts`) streams every available File's blob into a zip that
uploads to R2 as it's built (`archiver`'s `ZipArchive` + `@aws-sdk/lib-storage`'s `Upload`, new deps),
alongside `manifest.json` (metadata, checksums, `file_links`). New routes: `POST/GET /api/files/export`
(trigger + history, `files.export`-gated), `GET /api/files/export/[id]/download` (presigned URL, no bearer
token needed — owner is already signed in), `/api/internal/files/export-worker` (the new 5-minute cron's
target). The cheap expiry sweep rides the existing one-minute route instead.

**Verified:** 24/24 new pgTAP (`files_media_organization_export.sql`), including two real bugs pgTAP caught
before anything depended on them (fixed same session, see the fix migration's own header): a scalar-return
claim function that answered "there's a job" even when the queue was empty, and a `RETURNING` clause that
read `object_key` after its own `UPDATE` had already nulled it. `npm run check` clean (only the 3 known-stale
"union type too complex" errors remain). Prettier clean on all touched `.ts`. `npm run db:types` regenerated.

**Not yet done:** no frontend at all — no "Export everything" button, no status/download UI. No unit tests
for `organization-export.ts` (only pgTAP covers the DB layer so far). Nothing browser-checked or
email-checked (the export worker needs its own cron active, which needs deployment to add Vault secret
`files_export_worker_target_url` — a new gate, not yet in ROADMAP.md's approval-gates section — see
`parts/8B.md`). Real end-to-end (a zip actually built and downloaded) cannot happen locally any more than
8A's purge could.

**Exact next action:** Build the frontend trigger — an owner-only "Export everything" action in the Files
workspace toolbar (`src/routes/(app)/files/+page.svelte`), calling `POST /api/files/export`, polling
`GET /api/files/export` for status, and using the download route once `available`. Then add the new Vault
secret note to ROADMAP.md's approval gates.

**Blocker (campaign-wide):** the upload/processing worker does not run locally; nothing async can be
browser-verified end to end. Test reads with existing checked photos (Raad LTD has 12).

**Browser note:** the Chrome tab runs hidden, which pauses animation frames, slows timers and never loads
`loading="lazy"` images — drive pages with javascript and read the DOM. Role checks: impersonate in SQL
inside a rolled-back transaction; Raad LTD org `18f0d717-904e-48d8-bd99-9df7e3844cda`.

**Known stale pgTAP (not regressions):** `files_manage_actions.sql` 15–16, 23; `files_media_central_catalog.sql`
16. `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192`. Supabase CLI is `npx supabase`; a fresh
local pgTAP run needs `npx supabase db reset --local` first (test db does not auto-rebuild). Do not run
`supabase db query --linked -f <file>` for anything beyond read-only inspection — direct remote SQL writes
are blocked by this environment's auto-mode classifier; use a normal timestamped migration + `db push
--linked` instead, even for a same-day fix (see the 141500 migration for the precedent).
