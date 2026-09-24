# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 7B-3 — File Manager fast at 20k+ files (roadmap 7B-3). 7B-2 closed 2026-09-24.

**Exact next action:** Waiting on Jafar: (1) approve the design below, (2) say where timing tests may run —
the rolled-back tests that swap policies on the shared remote DB were stopped by the permission guard.
Measured 2026-09-24 (20k files, 5k linked to a client, owner): all 18 ms, rare label 429 ms, dense label
729 ms, caption search 9.3 s, no-match search 9.5 s. Swapping the five Files SELECT policies to the project's
`(select private.current_organization())` + `(select private.has_permission((select private.current_organization()), 'files.view'))`
once-per-query form (same rules; sound because `organization_members` is UNIQUE(user_id)) gave: all 46 ms,
rare 60 ms, dense 24 ms, but searches still ~4 s — the remaining cost is per-link `can_view_linked_entity`
plus the per-entity-type record-name EXISTS in `list_files` search. Field-worker (no files.view) path not yet
timed. Bench script lives only in the old session scratchpad; rebuild it from this note.

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked".

**Browser note:** a blank page with "Failed to hydrate … reading 'call'" is a stale Vite cache — hard reload.
The browser window is narrow; drive pages with javascript. Bits UI menus do not open from a script click.

**Known stale pgTAP (not regressions):** `files_manage_actions.sql` 15–16, 23; `files_media_central_catalog.sql`
16; `files_media_upload_pipeline.sql`. `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192`; its 3
"union type too complex" errors pre-date 7A. Supabase CLI is `npx supabase`.

**Pointers:** roadmap 7B-3 entry; `docs/files-media-behavior-contract.md` Part 7B.
