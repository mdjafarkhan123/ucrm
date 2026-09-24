# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 7B-2 — captions and labels shown (roadmap 7B-2). Built and pushed 2026-09-24; only the
browser check is left. Then 7B-3 (File Manager fast at 20k+ files).

**Exact next action:** Browser-check 7B-2 on Raad LTD (owner login), then commit memory and start 7B-3:
1. `/files` rail lists labels; clicking "After" shows `test-visit-photo.jpg` only; the pencil opens Manage
   labels (owner) and is absent for the sales login.
2. Search "driveway" finds it by caption; tile and Lightbox show the caption.
3. Job `b6229fd7-…` work report editor shows caption + labels under the photo; Preview as client shows them.
4. Issue a customer link, change the caption, confirm `/w/<token>` still shows the old words.

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked".

**Browser note:** a blank page with "Failed to hydrate … reading 'call'" is a stale Vite cache — hard reload.
Screenshots sometimes time out; read state with javascript.

**Known stale pgTAP (not regressions):** `files_manage_actions.sql` 15–16, 23; `files_media_central_catalog.sql`
16; `files_media_upload_pipeline.sql`. `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192`; its 3
"union type too complex" errors pre-date 7A. Supabase CLI is `npx supabase`.

**Pointers:** roadmap 7B-2 and 7B-3 entries; `docs/files-media-behavior-contract.md` Part 7B.
