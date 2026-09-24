# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 7B-3 — File Manager fast at 20k+ files (roadmap 7B-3). 7B-2 closed 2026-09-24.

**Exact next action:** Run the performance-review design branch for `list_files` at 20k files: decide how to
keep identical visibility while not running the files/label-assignment RLS functions per row before the
filter (e.g. authorize once inside `list_files`, or a cheaper per-row policy). Present the verdict to Jafar,
then build and re-measure the five scenarios in the roadmap entry (All, rare label, dense label, caption
search hit, no-match search).

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked".

**Browser note:** a blank page with "Failed to hydrate … reading 'call'" is a stale Vite cache — hard reload.
The browser window is narrow; drive pages with javascript. Bits UI menus do not open from a script click.

**Known stale pgTAP (not regressions):** `files_manage_actions.sql` 15–16, 23; `files_media_central_catalog.sql`
16; `files_media_upload_pipeline.sql`. `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192`; its 3
"union type too complex" errors pre-date 7A. Supabase CLI is `npx supabase`.

**Pointers:** roadmap 7B-3 entry; `docs/files-media-behavior-contract.md` Part 7B.
