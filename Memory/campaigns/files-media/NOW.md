# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Done:** Parts 1–6D. Part 6D (branding logo adoption) finished 2026-09-23: migrations `20260923130000`,
`20260923140000` (bridge), `20260923150000` (bridge dropped), `20260923170000` (found-and-fixed
`private.linked_entity_exists` missing its `'organization'` branch — see ROADMAP.md) all pushed live; the
14-file frontend swap is complete and typechecked clean. Browser-verified as admin (office role has no
`settings.business.edit`, so it cannot edit branding): Save shows "One file is being checked for safety",
old logo keeps showing until promoted. DB-verified end to end by hand-promoting the File through
`finalize_file_processing` (the worker does not run locally) — it linked correctly and bumped
`organization_settings.branding_revision`. The frontend poll actually swapping the shown logo live was not
re-observed: the Chrome browser session crashed mid-verification, after the upload/save step but before the
promotion step. `contractor_settings_business.sql` pgTAP is green (32/32).

**Not yet selected** — three planned parts are dependency-ready (depend only on 4–5, already complete): 6E
(messages: reuse only), 6F (marketing asset upload), and Part 7 (customer publication/proof of work) or
Part 8 (trash/export/security/scale) may take priority instead. Ask Jafar which to build next — do not
assume an order.

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked".

**Flagged, not fixed:** `requireLinkedEntityAccess` job/visit comment overstates protection; old
`deleteAttachment` call sites not audited; a sales/finance rep who picks then discards a line photo before Save
will fail the orphan-cleanup `trashFile` call silently (no `files.trash`), same as existing best-effort error
handling already tolerates — the file just sits unattached in the library; `npm run check` needs
`NODE_OPTIONS=--max-old-space-size=8192` (3 old "union type too complex" errors, pre-existing, unrelated to
Files and Media); `customer-access.spec.ts`'s "hands over anything that is not a photo" / "shows a line photo"
/ "answers a broken storage read" tests fail on a pre-existing `file_name`/`display_name` mock mismatch,
unrelated to 6C (part of the "73 API unit tests already failing" note from earlier parts).

**Carried to Part 8:** purge must handle published `quote_version_lines.image_file_id` (FK has no ON DELETE)
and protected `file_links` (delete trigger still blocks).

**Pointers:** `docs/files-media-behavior-contract.md`, `Design/Files and Media/README.md`.
