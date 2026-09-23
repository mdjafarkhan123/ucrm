# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Done:** Parts 1–5, 6A (Invoice), 6B (Quote, closed 2026-09-23). Part 6 sub-part table is in ROADMAP.md.

**Uncommitted:** Parts 6A and 6B are in the working tree but not git-committed. The tree also holds another
agent's marketing changes, so stage only Files-and-Media paths. Ask Jafar before committing.

**Active part: 6C — shared line-item photo migration** (depends on 6B, now ready). Move the per-line photo
box in `ProductsAndServicesBlock.svelte` (used by Quote, Request, Job, Visit) off `public.attachments` onto
the File Manager in one pass. Quote's `quote_version_lines.image_attachment_id` and the `'lines'` block of
`private.quote_customer_document` still read legacy `attachments` and must keep the sent-quote "historical
truth" rule (`docs/files-media-behavior-contract.md`, Part 6B paragraph shows the pattern used for quote files).

**Exact next action:** ask Jafar whether to commit 6A+6B first; then research/plan 6C (read the component and
every `image_attachment_id` user) and present the plan before writing a migration.

**Blocker (campaign-wide):** the upload processing worker does not run locally, so new uploads stay "Still
being checked". Verify with files that are already `available`.

**Flagged, not fixed:**
- The `job`/`visit` comment in `requireLinkedEntityAccess` (`src/lib/server/access/collaboration.ts`)
  overstates what protects `/api/files/links` attach on a job/visit.
- Not yet audited: whether any old `deleteAttachment` call site still deletes a shared R2 object outright.

**Pointers:** `docs/files-media-behavior-contract.md`, `Design/Files and Media/README.md`.
