# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Done:** Parts 1–6F closed (6F commit `8810cb2`). Image blocks upload through the File Manager
(`origin_type marketing_campaign`, role `campaign_image`); public route `(public)/ci/[campaignId]/[fileId]`
serves the picture to recipients' mail clients. Not built: a "browse the library" reuse picker for image
blocks (direct-upload-only) — Jafar may ask later.

**6F browser-verified 2026-09-23** (worker simulated in SQL): two real bugs fixed — uploads refused as "not
found" (`2e284ac`) and broken images in the email preview, now signed R2 links (`d94df02`). Leftover test
draft "6F image check" (`bc699e33…`) can be deleted.

**Exact next action:** Ask Jafar to confirm starting Part 7 (customer publication / proof of work) — Part 8
depends on 7 — then read Part 7's ROADMAP row and start it.

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked".

**Known stale pgTAP (not 6E regressions):** `files_manage_actions.sql` 15–16, 23 and
`files_media_central_catalog.sql` 16 still expect the pre-`20260923100000` hard Trash refusal;
`files_media_upload_pipeline.sql` calls an old `register_pending_file` signature. Update when a part touches them.

**Pointers:** `docs/files-media-behavior-contract.md`, `Design/Files and Media/README.md`.
