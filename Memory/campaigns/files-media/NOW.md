# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 7D — Selected-file customer shares + "Shared with customers" view (roadmap 7D).

**Exact next action:** Plan 7D. Research how mature products share chosen files with a customer (e.g. Jobber,
CompanyCam, Google Drive/Dropbox share links: expiry, revoke, what the customer sees, download vs view), then
grill Jafar on the open choices and record approved behavior in a `parts/7D-*.md` packet before any code.
Contract already fixes: revocable, expiring, names only its chosen Files, reveals nothing else, no live folders;
the "Shared with customers" rail view appears only once shares exist (`docs/files-media-behavior-contract.md`,
"Customer visibility and historical truth").

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked".
Test with existing checked photos (Raad LTD has 12) attached through a record's "Add" picker.

**Browser note:** the Chrome tab runs hidden, which pauses animation frames and slows timers — drag libraries
and animations stall; drive pages with javascript and read the DOM. Another session's server-file edits reload
the dev page, so keep each check inside one script. Role checks: impersonate in SQL inside a rolled-back
transaction; Raad LTD org `18f0d717-904e-48d8-bd99-9df7e3844cda`.

**Known stale pgTAP (not regressions):** `files_manage_actions.sql` 15–16, 23; `files_media_central_catalog.sql`
16; `files_media_upload_pipeline.sql`. `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192`. Supabase
CLI is `npx supabase`; run SQL files with `npx supabase db query --linked -f <file>` (~2 min limit per call).
