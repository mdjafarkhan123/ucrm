# Jobs: Current Checkpoint

- Goal: Build simpler contractor Jobs and Visits without losing proven Jobber behavior.
- State: 15e (Work Report), design approved. **DB foundation + app layer both written.** DB: migration
  `supabase/migrations/20260913100000_job_reports_foundation.sql` (4 tables, RLS all-closed, 9 RPCs),
  applied + verified on dev, `database.types.ts` regenerated. App layer: all files below written,
  `npm run check` and `npx prettier --check` both clean. **Nothing is committed yet.**
- Files written this part: `src/lib/server/jobs/report-access-links.ts`, `src/lib/server/jobs/report-errors.ts`,
  `src/lib/server/validation/job-reports.schema.ts`, `src/lib/jobs/report-types.ts`, `src/lib/jobs/report-api.ts`,
  `src/routes/api/jobs/[id]/report/+server.ts` (GET/PUT), `src/routes/api/jobs/[id]/report/access-links/+server.ts`
  (POST), `src/routes/api/public/jobs/report/[token]/view/+server.ts`,
  `src/routes/(public)/w/[token]/+page.server.ts` + `+page.svelte` + `files/[attachmentId]/+server.ts`,
  `src/routes/(app)/jobs/[id]/report/preview/+page.server.ts` + `+page@.svelte`,
  `src/lib/components/jobs/CustomerJobReportDocument.svelte`, `JobWorkReportCard.svelte`,
  `EditJobReportDialog.svelte`. Job detail page (`(app)/jobs/[id]/+page.svelte`) wired: card mounted after
  `JobSignaturesCard` (only when `editable`), `···` menu gains Preview/Print/Copy-link once `has_content`
  (via `workReportCard` bind:this exposing `openPreview()`/`copyLink()`, and an `onStateChange` callback).

## Exact next action

**Browser-verify, then commit.** A fork agent was mid-way through the click-through checklist below when
this session paused — it may have finished (and possibly applied small fixes) or may have been cut off.
Re-run whatever wasn't confirmed, then commit:
1. Open a job → "Work report" rail card shows (empty state if unsaved).
2. Edit report dialog: toggles, signature select, summary, photo grid, per-visit checklist checkboxes all
   render (including graceful empty states with no photos/no answered checklist items); unchecking "Show
   the work list" clears "Show prices" client-side.
3. Save → toast, card shows "Ready to share" + summary line, has_content flips true.
4. Job `···` menu gains Preview / Print / Copy work report link only once has_content.
5. Preview opens `/jobs/[id]/report/preview` correctly (no app chrome); Copy link issues a real link (check
   the POST to `/api/jobs/[id]/report/access-links` returns 200 + `url`); open that `/w/<token>` link in a
   clean tab and confirm the public document renders with no console errors.
6. Then: `git add` the migration + all report files + the two touched pages (`database.types.ts` and
   `Memory/`), commit, report done to Jafar.

## Non-rediscoverable decisions the app layer must honor

- Always-current: nothing snapshotted; a cleared answer or un-checked photo drops from every sent link at
  once. Un-check ≠ delete the underlying attachment (FK is restrict).
- The drawn signature image is NOT streamed on the public page in this part — signature shows name/role/
  type/statement/method/date only. Small follow-up if Jafar wants the image shown.
- `save_job_report` writes a feed line only on the empty↔content crossing (silent on photo swaps).

## Pointers

- App-layer precedents: `(app)/invoices/[id]/+page.svelte` (`copyClientLink`, `openCustomerView`,
  `invoiceMenuItems`), `(public)/i/[token]/`, `src/lib/checklists/api.ts` (`fetchVisitChecklists`),
  `src/lib/collaboration/api.ts` (`isImageAttachment`, `attachmentImageUrl`, `fetchAttachments`),
  `JobSignaturesCard.svelte` + `CollectJobSignatureDialog.svelte`.
- Svelte MCP autofixer doesn't run SCSS — false-flags `&__` and `//`; `npm run check` is the real gate.

Resume command: `read memory and continue the Jobs campaign`.
