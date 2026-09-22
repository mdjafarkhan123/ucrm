# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Just closed:** Part 5F — record-scoped upload permission, extended to every linked-entity type in one pass,
plus mounting `RecordFilesCard` on Visit. Committed `d531915`.

**What shipped (see `docs/files-media-behavior-contract.md` for the full write-up):**

- `POST /api/files/uploads` and its `/complete` route now authorize a record-scoped upload by the record's own
  write permission (`requireLinkedEntityAccess`), not the library-wide `files.manage`. Covers every
  `origin_type`: client/property/request/quote/job_expense/job/visit.
- `FilePicker`'s Upload button follows the same rule via a new `canManageRecord` prop.
- `VisitRecordsDialog` replaces its old `AttachmentsCard` with `RecordFilesCard` (matching the Job/Request
  shape); files left the dialog's staged "Save records" bar.
- Pre-existing bug fixed: `FileUploader` inside `FilePicker` was never bound, so its own Upload button silently
  did nothing since Part 4 shipped.

**Browser-verified 2026-09-22** (Raad LTD, field member `dev.jafarkhan@gmail.com`, via a scripted Playwright
check — no live GUI tool was available this session): Job #20 and its visit both show the Upload button for a
field member with no `files.manage`, and an upload reaches `processing_state = 'pending'` with the correct
`origin_type`/`origin_id` (confirmed in the database directly, not just the UI). Sales/finance on a quote was
**not** browser-tested — Quote has no `RecordFilesCard` yet (that's Part 6); Jafar agreed 2026-09-22 to skip
that live check and rely on the backend fix being record-type-generic until Part 6 ships the quote screen.

**Verified:** `npm run check` clean (only the 3 pre-existing `resolve()` union errors), `npx prettier --check`
clean on every touched file, all touched component specs pass (15/15 across `FilePicker`, `RecordFilesCard`,
`JobVisitsSection`).

**Test state in Raad LTD (owner login, left in place on purpose):** Job #20 ("Solar setup quote (revised
scope) v2") has one visit, Sep 22 2026, with Field Tester assigned. Two test files
(`part5f-test-upload.txt`, `visit-test-upload.txt`) sit in `pending` processing state on that job/visit — safe
test data, not customer content; fine to leave.

**Exact next action (resume here):**

Ask Jafar: forms and job expense receipts still run on the old `AttachmentsCard` and were never started, but
Part 5's roadmap gate names them. Decide whether they finish Part 5 or move into Part 6, then select the next
slice.

**Other blockers (unrelated to this work):**

- An upload still cannot be watched turning usable until deployment sets the values in ROADMAP "Approval
  gates" (worker secret, scanner host/port, two Vault secrets, and the cron job that ships switched off).
  Until then every upload correctly stops at "Still being checked" / `processing_state = 'pending'`.

**Non-obvious risks:**

- `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192`; it OOMs otherwise. Three
  "union type too complex" errors in `(app)/+layout.svelte`, `OpportunityBriefDrawer` and `invoices/new`
  are pre-existing `resolve()` route-union noise, not this work.
- `npm run test:unit` still fails 71 tests across quotes, settings and team. All predate this work.
- Flagged, not fixed: the `job`/`visit` branch comment in
  `src/lib/server/access/collaboration.ts`'s `requireLinkedEntityAccess` overstates what actually protects
  `/api/files/links` attach on a job/visit — real but narrow gap, pre-existing, not introduced here. Worth a
  dedicated look later, not blocking.

**Pointers:**

- `docs/files-media-behavior-contract.md` — the approved model, now current through Part 5F/Visit
- `Design/Files and Media/README.md` — the workspace blueprint
