# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 7B-4 — clients/properties/requests/invoices SELECT policies checked once per query (roadmap 7B-4).

**Exact next action:** `20260924210000_record_views_checked_once_per_query.sql` is LIVE (pushed 2026-09-24).
Spot-check Clients, Requests, Invoices lists and Files search on Raad LTD in the browser (or Jafar confirms
he did) → close 7B-4 and select 7C. Direct SQL reads of live data are blocked by the auto-mode classifier;
the browser check needs the Chrome extension connected. Evidence: same rows old vs new for all six roles;
admin 20k clients 13 s → 9 ms; other roles at 5k 3.3–5.5 s → under 0.07 s.

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked".

**Browser note:** a blank page with "Failed to hydrate … reading 'call'" is a stale Vite cache — hard reload.
The browser window is narrow; drive pages with javascript. Bits UI menus do not open from a script click.
Role checks: impersonate in SQL (`set local role authenticated` + `request.jwt.claims`) inside a rolled-back
transaction; Raad LTD org `18f0d717-904e-48d8-bd99-9df7e3844cda`.

**Known stale pgTAP (not regressions):** `files_manage_actions.sql` 15–16, 23; `files_media_central_catalog.sql`
16; `files_media_upload_pipeline.sql`. `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192`; its 3
"union type too complex" errors pre-date 7A. Supabase CLI is `npx supabase`; run SQL files with
`npx supabase db query --linked -f <file>` from the repo root (~2 min limit per call).

**Pointers:** roadmap 7B-4 entry; `supabase/migrations/20260924190000_files_media_link_visibility_once_per_query.sql`.
