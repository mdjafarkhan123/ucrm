# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 7B-3 — File Manager fast at 20k+ files (roadmap 7B-3).

**Exact next action:** Jafar approves the push of `20260924190000_files_media_link_visibility_once_per_query.sql`
(dry-run shows it is the only pending migration) → `npx supabase db push --linked` → browser check on Raad LTD
(owner: All, client-name search, Not attached, a client's Files tab; field member: an assigned job's files) → close
7B-3 and select 7C. Rolled-back 20k-file tests, old vs new, identical results for owner, finance and field:
client search 3.7–5.3 s → 45–64 ms, Not attached 6.8–9.4 s → 0.18–0.26 s, field job files 13.2 s → 0.8 s.
Field members can only reach `on_record` (server gate in `src/routes/api/files/+server.ts`), so the files policy's
per-file test on other views is unreachable for them and was left as is.
Approved by Jafar 2026-09-24, after 7B-3: move the clients/properties/requests/invoices SELECT policies to the
same once-per-query form (identical visibility, rolled-back old-vs-new digest check, then push).

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked".

**Browser note:** a blank page with "Failed to hydrate … reading 'call'" is a stale Vite cache — hard reload.
The browser window is narrow; drive pages with javascript. Bits UI menus do not open from a script click.

**Known stale pgTAP (not regressions):** `files_manage_actions.sql` 15–16, 23; `files_media_central_catalog.sql`
16; `files_media_upload_pipeline.sql`. `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192`; its 3
"union type too complex" errors pre-date 7A. Supabase CLI is `npx supabase`; run SQL files with
`npx supabase db query --linked -f <file>` from the repo root (~2 min limit per call).

**Pointers:** roadmap 7B-3 entry; `docs/files-media-behavior-contract.md` Part 7B.
