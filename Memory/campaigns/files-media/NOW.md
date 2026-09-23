# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** 7B — Photo captions and labels (Before/After/Damage…). Not started; 7A closed 2026-09-24.

**Exact next action:** Ask Jafar to approve starting 7B. Then research how Jobber / CompanyCam handle photo
captions and labels (who adds them, where they show, whether labels are a fixed list), and propose the approach
before any schema. Roadmap entry 7B holds the completion gate.

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked" —
test with already-available photos.

**Known stale pgTAP (not regressions):** `files_manage_actions.sql` 15–16, 23; `files_media_central_catalog.sql`
16; `files_media_upload_pipeline.sql` (old `register_pending_file` signature). `npm run check` needs
`NODE_OPTIONS=--max-old-space-size=8192`; its 3 "union type too complex" errors pre-date 7A.

**Pointers:** `docs/files-media-behavior-contract.md` (Part 7A paragraph), `Design/Files and Media/README.md`.
