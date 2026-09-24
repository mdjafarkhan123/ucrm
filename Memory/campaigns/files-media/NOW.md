# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 7D-2 — manage customer file shares (roadmap 7D-2; 7D-1 closed 2026-09-25).

**Exact next action:** Build 7D-2 from `docs/files-media-behavior-contract.md`, "How a selected-file share
works": the "Shared with customers" rail view (only once a share exists), Turn off, the File details "Shared
with" list, the expired/turned-off contact page (business phone + email), Send by email/text via the Client's
inbox conversation, the turn-off Client activity entry, and the Trash warning count. Builds on 7D-1's
`file_shares` / `file_share_items` tables, `create_file_share` / `resolve_file_share` functions
(`supabase/migrations/20260925100000_files_media_customer_shares.sql`) and `/f/[token]`, which today answers
every dead link with the same 404 page (`+error.svelte`) — 7D-2 must keep unknown links a plain 404 while
turned-off/expired ones show the contact page.

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked".
Test with existing checked photos (Raad LTD has 12). A live test share exists: Greenfield Property Group, 2 files.

**Browser note:** the Chrome tab runs hidden, which pauses animation frames, slows timers and never loads
`loading="lazy"` images — drive pages with javascript and read the DOM. Role checks: impersonate in SQL inside
a rolled-back transaction (call `private.*` as postgres with jwt claims set, then `set local role
authenticated` for table reads); Raad LTD org `18f0d717-904e-48d8-bd99-9df7e3844cda`.

**Known stale pgTAP (not regressions):** `files_manage_actions.sql` 15–16, 23; `files_media_central_catalog.sql`
16; `files_media_upload_pipeline.sql`. `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192` and has 3
pre-existing "union type too complex" errors. Supabase CLI is `npx supabase`; run SQL files with `npx supabase
db query --linked -f <file>` (~2 min limit per call).
