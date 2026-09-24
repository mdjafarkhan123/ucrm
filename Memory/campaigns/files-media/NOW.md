# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 7D-1 — make and open a customer file share (roadmap 7D-1; 7D-2 follows).

**Exact next action:** Build 7D-1 from `docs/files-media-behavior-contract.md`, "How a selected-file share
works" (approved 2026-09-24). Copy the proven link shape: `job_report_access_links` (hash-only token, expiry,
revoke reason, view tracking) and its `/w/[token]` page + file route; `/m/[token]` streams one R2 object.
New `files.share` permission for owner/admin/office. Apply the performance-review gate to the share list and
customer page before building (50-file cap per share).

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked".
Test with existing checked photos (Raad LTD has 12) attached through a record's "Add" picker.

**Browser note:** the Chrome tab runs hidden, which pauses animation frames and slows timers — drag libraries
and animations stall; drive pages with javascript and read the DOM. Another session's server-file edits reload
the dev page, so keep each check inside one script. Role checks: impersonate in SQL inside a rolled-back
transaction; Raad LTD org `18f0d717-904e-48d8-bd99-9df7e3844cda`.

**Known stale pgTAP (not regressions):** `files_manage_actions.sql` 15–16, 23; `files_media_central_catalog.sql`
16; `files_media_upload_pipeline.sql`. `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192`. Supabase
CLI is `npx supabase`; run SQL files with `npx supabase db query --linked -f <file>` (~2 min limit per call).
