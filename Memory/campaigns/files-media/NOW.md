# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 8B, backend and frontend both done, not yet committed. Design fully recorded in
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

**8B frontend shipped (2026-09-25, uncommitted):** `can_export` added to `GET /api/files`'s response
(`hasPermission(access, 'files.export')`) and to `FileListPage`/`api.ts`. New `FileExportButton.svelte`,
mounted only on the "All files" view when `can_export` is true — a compact "Export everything" button that
POSTs, polls `GET /api/files/export` every 5s while the latest row is `queued`/`processing` (stops itself
once it settles, same bounded-poll shape as `RecordFilesCard`/`ImportDoneStep`), then shows a Download button
+ size/count/date once `available`, or the last error if `failed`. `npm run check`/eslint/prettier/svelte
autofixer all clean. ROADMAP.md's approval-gates section already had the `files_export_worker_target_url`
Vault-secret note from the backend commit — nothing more to add there.

**Browser-verified live on Raad LTD (2026-09-25):** started a second local dev server (this worktree's own,
port 5199 — a sibling worktree already held 5173/5174) and drove it with Playwright directly (no
`chromium-cli` binary in this environment). Owner login (`info.socialmediauser1@gmail.com`) sees the button,
clicking it gets a real 202 with a queued `organization_exports` row, the toast and "Preparing export…"
state both show. Office-role login (`dev.jafarkhan+office@gmail.com`) never sees the button and the page
throws no errors (the console 403s present on that role are pre-existing, unrelated dashboard widgets —
marketing readiness, invoices, onboarding checklist — checked by URL, not from anything this part touched).

**Not yet done:** no unit tests for `organization-export.ts` (only pgTAP covers the DB layer). The zip build
itself is still unverified end to end — the export-worker cron is not active (needs the Vault secret +
deployment), so a real run only ever reaches `queued` locally, same limitation 8A's purge had.

**Exact next action:** Commit the 8B frontend, then start Part 8C (security/accessibility/scale
verification) or ask Jafar if he wants the export cron activated on the next deploy first.

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
