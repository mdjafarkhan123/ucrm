# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 7C — Work Report presentation: order, sections, before/after pairs (roadmap 7C).

**Exact next action:** 7C built (`0683090` database, `94f391c` app) and its migration is live (pushed
2026-09-24). Browser check on a Raad LTD job — add photos (label pre-sort), drag + arrow moves, heading + note,
pair + swap + split, Preview as client (2-across, pair side by side, phone width), Copy link → rearrange →
"changed since you sent it" notice → Copy updated link clears it. Then close 7C and select 7D. Local db: test
with `npx supabase test db --local <files>`.

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked".

**Browser note:** a blank page with "Failed to hydrate … reading 'call'" is a stale Vite cache — hard reload.
The browser window is narrow; drive pages with javascript. Bits UI menus do not open from a script click.
Role checks: impersonate in SQL (`set local role authenticated` + `request.jwt.claims`) inside a rolled-back
transaction; Raad LTD org `18f0d717-904e-48d8-bd99-9df7e3844cda`.

**Known stale pgTAP (not regressions):** `files_manage_actions.sql` 15–16, 23; `files_media_central_catalog.sql`
16; `files_media_upload_pipeline.sql`. `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192`; its 3
"union type too complex" errors pre-date 7A. Supabase CLI is `npx supabase`; run SQL files with
`npx supabase db query --linked -f <file>` from the repo root (~2 min limit per call).

**Pointers:** `parts/7C-work-report-presentation.md`; `docs/files-media-behavior-contract.md` (work report sections).
