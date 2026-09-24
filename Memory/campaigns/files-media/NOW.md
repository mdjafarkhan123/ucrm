# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 7B-3 — File Manager fast at 20k+ files (roadmap 7B-3). 7B-2 closed 2026-09-24.

**Exact next action:** Jafar runs `! npx supabase db push --linked` (the permission guard blocked Claude's push)
for `20260924170000_files_media_fast_at_scale.sql` (committed, not yet applied). Then fix the one cause left:
per-link `private.can_view_linked_entity` (~0.7 ms each). Rolled-back tests at 20k files, old vs new results
identical: all/labels/caption/no-match search now 30–100 ms, but client-name search matching 5k files 4.1 s,
"Not attached" 3.7 s, field worker on_record 7.7 s (plan scans every file running `file_has_visible_link`).
Candidate: in the `file_links` policy, skip the per-row check when the caller's org-wide scope already covers
the entity type (once-per-query booleans), and make on_record drive from the record's links. Must keep
visibility identical (entity-existence checks inside can_view_invoice/quote/visit/expense). Compare old vs new
with the rolled-back old/new digest bench (rebuild from this note; one run per user, Management API times out ~2 min).
Clients/properties/requests/invoices policies are also per-row; outside this campaign — ask Jafar first.

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked".

**Browser note:** a blank page with "Failed to hydrate … reading 'call'" is a stale Vite cache — hard reload.
The browser window is narrow; drive pages with javascript. Bits UI menus do not open from a script click.

**Known stale pgTAP (not regressions):** `files_manage_actions.sql` 15–16, 23; `files_media_central_catalog.sql`
16; `files_media_upload_pipeline.sql`. `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192`; its 3
"union type too complex" errors pre-date 7A. Supabase CLI is `npx supabase`.

**Pointers:** roadmap 7B-3 entry; `docs/files-media-behavior-contract.md` Part 7B.
