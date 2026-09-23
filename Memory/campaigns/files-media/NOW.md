# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 7A — Work Report photos from the File Manager. Built and committed `7fcbc18`; migration
`20260924100000` pushed live; pgTAP `files_media_work_report_photos.sql` 22/22; typecheck clean for touched files.
Same migration fixed a live bug: "Used in" failed for every File since 6F (`file_link_marketing_campaign`).

**Exact next action:** Browser-verify 7A on Raad LTD (office login), then close 7A in ROADMAP:
1. A File's details panel loads "Used in" again (any file, incl. a campaign image).
2. Job → Edit work report shows job + visit photos (File Manager tiles), saves, Preview as client shows them.
3. Copy work report link → open `/w/<token>`: photos load; "Used in" shows the job as customer-received.
4. Trash that photo → strongest dialog; customer page shows "Photo removed"; Restore brings it back.
Then ask Jafar to start 7B (captions + labels).

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked" —
use already-available photos for step 2.

**Known stale pgTAP (not regressions):** `files_manage_actions.sql` 15–16, 23; `files_media_central_catalog.sql`
16; `files_media_upload_pipeline.sql` (old `register_pending_file` signature). `npm run check` needs
`NODE_OPTIONS=--max-old-space-size=8192`; its 3 "union type too complex" errors pre-date 7A.

**Pointers:** `docs/files-media-behavior-contract.md` (Part 7A paragraph), `Design/Files and Media/README.md`.
