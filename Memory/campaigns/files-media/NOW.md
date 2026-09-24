# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 7B-1 — captions and labels (roadmap entry 7B-1). Built, committed, migration applied; File
Manager panel + Manage labels verified in the browser 2026-09-24.

**Exact next action:** Finish 7B-1's browser check, then close it and start 7B-2:
1. Job `b6229fd7-c31a-44ed-8448-5f1d5fd18d64` → Visits → Past → "Extra trim visit" ⋮ → Notes, photos and files.
   Hover the photo → tag button (bottom-left) → "Caption and labels" dialog opens on top of the visit dialog;
   save a caption, confirm it shows in File Manager for `test-visit-photo.jpg`.
2. Re-check Manage labels: rename box now takes focus, list no longer indented.
3. Field-member rule: cannot log in as them yourself — either ask Jafar, or prove `canDescribeFile` via SQL
   with `set local role authenticated` + jwt claims for the field user (file_links visible only on assigned jobs).

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked".

**Browser note:** if a page goes blank with "Failed to hydrate … reading 'call'", it is two Svelte runtime
copies from a stale Vite cache — hard reload (ctrl+shift+r), not a code bug. Screenshots sometimes time out;
read state with javascript instead.

**Known stale pgTAP (not regressions):** `files_manage_actions.sql` 15–16, 23; `files_media_central_catalog.sql`
16; `files_media_upload_pipeline.sql`. `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192`; its 3
"union type too complex" errors pre-date 7A.

**Pointers:** `docs/files-media-behavior-contract.md` (Part 7B paragraph), roadmap 7B-2 entry.
