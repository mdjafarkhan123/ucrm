# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Done:** Parts 1–6E closed (6E closed 2026-09-23; see its ROADMAP row).

**Exact next action:** Ask Jafar which part to build next — 6F (marketing asset upload), Part 7 (customer
publication / proof of work), or Part 8 (trash/export/security/scale) — then read that ROADMAP row and start it.

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked".

**Known stale pgTAP (not 6E regressions):** `files_manage_actions.sql` 15–16, 23 and
`files_media_central_catalog.sql` 16 still expect the pre-`20260923100000` hard Trash refusal;
`files_media_upload_pipeline.sql` calls an old `register_pending_file` signature. Update when a part touches them.

**Pointers:** `docs/files-media-behavior-contract.md`, `Design/Files and Media/README.md`.
