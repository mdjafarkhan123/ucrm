# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 7B-2 — show captions and labels (roadmap entry 7B-2). 7B-1 closed 2026-09-24.

**Exact next action:** Plan 7B-2, running performance-review's design branch first (label filter + caption
search change `list_files`, which grows with an organization's files). Then build:
1. Work report: add `caption` and `labels` to each photo in the document builder in
   `20260924100000_files_media_work_report_photos.sql` (the `'photos'` jsonb) so issued links freeze them; show
   them in the editor and the customer view.
2. File Manager: a Labels filter in the left rail (under "Manage photo labels") and caption matching in search.
3. Optionally show the caption in the Lightbox under the file name.

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked".

**Browser note:** a blank page with "Failed to hydrate … reading 'call'" is a stale Vite cache (two Svelte
runtimes) — hard reload with ctrl+shift+r. Screenshots sometimes time out; read state with javascript.
Test photo with caption + "After" label: `test-visit-photo.jpg` on job `b6229fd7-…` visit "Extra trim visit".

**Known stale pgTAP (not regressions):** `files_manage_actions.sql` 15–16, 23; `files_media_central_catalog.sql`
16; `files_media_upload_pipeline.sql`. `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192`; its 3
"union type too complex" errors pre-date 7A.

**Pointers:** `docs/files-media-behavior-contract.md` (Part 7B paragraph), roadmap 7B-2 entry.
