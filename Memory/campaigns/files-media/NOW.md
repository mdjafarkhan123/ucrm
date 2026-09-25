# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 8 — Trash, export, security, and scale verification (roadmap 8; 7D-2b closed 2026-09-25).

**Exact next action:** Read ROADMAP part 8 and `docs/files-media-behavior-contract.md` (Trash and export
sections), then propose Part 8's slices to Jafar for approval before building. It needs the performance-review
verification branch.

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked".
Test with existing checked photos (Raad LTD has 12).

**Browser note:** the Chrome tab runs hidden, which pauses animation frames, slows timers and never loads
`loading="lazy"` images — drive pages with javascript and read the DOM. Role checks: impersonate in SQL inside a
rolled-back transaction; Raad LTD org `18f0d717-904e-48d8-bd99-9df7e3844cda`.

**Known stale pgTAP (not regressions):** `files_manage_actions.sql` 15–16, 23; `files_media_central_catalog.sql`
16; `files_media_upload_pipeline.sql`. `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192` and has 3
pre-existing "union type too complex" errors. Supabase CLI is `npx supabase`; run SQL files with `npx supabase
db query --linked -f <file>`.
