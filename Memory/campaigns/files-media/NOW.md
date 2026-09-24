# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 7B-4 — clients/properties/requests/invoices SELECT policies checked once per query (roadmap 7B-4).

**Exact next action:** Load the SQL skill gates, read the live SELECT policies on `clients`, `properties`,
`requests`, `invoices`, and rewrite them in the once-per-query form `20260924190000` used for `files`. Prove
identical visibility for owner, finance, sales, office and field in a rolled-back old-vs-new digest check at
scale, measure before/after, then ask Jafar to approve the push. After that, 7C.

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
