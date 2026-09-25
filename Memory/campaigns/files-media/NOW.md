# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 7D-2b — Send by email / Send by text (roadmap 7D-2b; 7D-2a closed 2026-09-25).

**Exact next action:** Build 7D-2b from `docs/files-media-behavior-contract.md`, "How a selected-file share
works", Delivery bullet. The raw link exists only in the create response, so the buttons belong on
`FileShareDialog.svelte`'s "Link ready" step. Hand the draft (client, channel, message + link) to
`/communications` in memory, not in the URL. Known gap to solve first: the inbox (`src/routes/(app)/communications/
+page.svelte`) builds conversations only from its latest 50 messages, and `?client=` falls back to another
conversation when that Client has none there; `ConversationComposer` has no initial-body prop; there is no
new-conversation path for text (email has `ManualEmailDialog`).

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked".
Test with existing checked photos (Raad LTD has 12). Live test shares: Greenfield Property Group, 2 files
(active) and 1 file (turned off).

**Browser note:** the Chrome tab runs hidden, which pauses animation frames (closed dialogs stay in the DOM with
`data-state="closed"`), slows timers and never loads `loading="lazy"` images — drive pages with javascript and
read the DOM. Role checks: impersonate in SQL inside a rolled-back transaction (`set_config('request.jwt.claims',
…)` then `set local role authenticated`); Raad LTD org `18f0d717-904e-48d8-bd99-9df7e3844cda`.

**Known stale pgTAP (not regressions):** `files_manage_actions.sql` 15–16, 23; `files_media_central_catalog.sql`
16; `files_media_upload_pipeline.sql`. `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192` and has 3
pre-existing "union type too complex" errors. Supabase CLI is `npx supabase`; run SQL files with `npx supabase
db query --linked -f <file>` (~2 min limit per call; only the last statement's rows print).
