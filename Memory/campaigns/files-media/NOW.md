# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 8B closed 2026-09-25 — backend (`d7d31ee`) and frontend (`b26773e`) both committed,
browser-verified live on Raad LTD (owner sees and can start an export; office role cannot). Full outcome is
in ROADMAP.md's Part 8B row; design detail (permission model, cron split, manifest shape) lived in
`parts/8B.md`, now deleted since it's fully promoted into the roadmap entry and the code itself.

**Known limitation carried into 8C:** the zip build itself is still unverified end to end — the
export-worker cron (`files-export-worker-wake-five-minutes`) is not active (needs Vault secret
`files_export_worker_target_url` + deployment), so a real run only ever reaches `queued` locally, same
limitation 8A's purge had.

**Active part:** 8C (security, accessibility, scale verification) — Jafar chose to do it now, cron activation
waits for deployment like every other worker cron in this campaign.

**8C accessibility slice done 2026-09-25 (uncommitted):** added `@axe-core/playwright` as a devDependency (the
established automated a11y checker, matches Deque/axe-core industry convention) and ran it, logged in as Raad
LTD owner via a scratch Playwright driver script (not committed — chromium-cli isn't installed here), against
six real Files-workspace states: the grid view, details panel, Trash confirm dialog (with the "shared with a
customer" warning shown), Share-with-customer dialog, list layout, and the Lightbox. Found and fixed 2 real,
repo-wide bugs, not confined to Files: `ToastViewport.svelte`'s `<div aria-label="Notifications">` had no
valid role for that attribute (fixed: `role="region"`, the same pattern Radix's toast viewport uses) — this
component mounts on every page, so the fix isn't Files-specific. And the hidden native file-input triggered by
the "Upload" button had no accessible name in two places sharing the same bug: `src/routes/(app)/files/+page.svelte`
and `PendingFilesCard.svelte` (used by every create-form's file picker — Client, Request, Job expense, Invoice,
Quote). Both got `aria-label="Upload files"`. Re-ran after fixing: 0 violations across all six states.

**Not yet done (accessibility):** only the owner role and only the File Manager's own pages were checked —
no pass yet on the create-form dialogs that reuse `PendingFilesCard` on their own pages, nor keyboard-only
(tab-order) navigation without a mouse. Accessibility fixes are committed (`96c8c76`).

**8C security/permission slice done 2026-09-25 (nothing to commit — pure verification, no code changed):**
queried `role_permissions` live for the ground truth matrix (owner: view+manage+share+trash+export; admin/
office: view+manage+share+trash, no export; sales/finance: view only; field: none of files.* — field's file
access is entirely job-scoped via `on_record` reads gated on the record's own permission, confirmed separately).
Logged in as all six real Raad LTD role accounts from CLAUDE.md and hit the actual API routes directly
(Playwright's `context.request`, sharing the login cookie) — not just checked what the UI hides:
`GET /api/files` returns `can_manage/can_share/can_trash/can_export` matching the matrix exactly for every
role; `POST /api/files/shares`, `POST /api/files/uploads`, `POST /api/files/[id]/trash`, `POST
/api/files/export`, and `GET /api/files/export/[id]/download` all correctly 403 for every role the matrix
says shouldn't reach them (probes used well-formed payloads per each Zod schema, so the 403 is the
permission gate itself, not a validation-error false positive). Field's `GET /api/files` (general library)
correctly 403s, while its job-scoped `?view=on_record&entity_type=job&entity_id=<their assigned job>` read
correctly 200s. Zero gaps found — no fix needed. Cross-tenant isolation itself (a different org reaching
Raad LTD's files) was not re-tested here; it's covered by each part's own pgTAP (Part 2's 49 assertions,
8B's 24/24) at the RLS layer, a different layer than this session's role/permission-route check.

**Exact next action (Jafar's call, 2026-09-25 — do it next session):** measure real performance at a large
file count for the surfaces 7B-3/7B-4 never load-tested: caption/label search (7B-2) and the Shared-with-
customers list (7D-2a). Set up a large synthetic file count for Raad LTD (matching 7B-3/7B-4's rolled-back
old-vs-new method) and measure, don't assume. Part 8B's export-build-time measurement stays separately
blocked until the export-worker cron is active on a real deploy — note that as a known gap in 8C's
completion rather than waiting on it.

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
