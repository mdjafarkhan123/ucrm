# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 7B-4 — clients/properties/requests/invoices SELECT policies checked once per query (roadmap 7B-4).

**Exact next action:** Jafar approves the push of `20260924210000_record_views_checked_once_per_query.sql`
→ `npx supabase db push --linked` (dry-run first) → spot-check Clients, Requests, Invoices lists and Files search
on Raad LTD → close 7B-4 and select 7C. Rolled-back tests, old vs new, identical rows for all six roles: admin at
20k clients, clients list 13 s → 9 ms; owner/office/sales/finance/field at 5k, 3.3–5.5 s → under 0.07 s; field
new-only at 20k under 0.07 s. The old rules exceed the 2-min limit at 20k for most roles; turning that limit off
on the live database was blocked, so old-vs-new sameness is proven at 5k (admin at 20k).

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
