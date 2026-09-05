# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- **7b (Void / Bad debt+restore / Mark received+reopen) CLOSED — browser-verified end to end, not yet
  committed.** Wired the five already-built lifecycle commands to the invoice detail "More" menu via one
  `/api/invoices/[id]/lifecycle` route (discriminated `action`), one `InvoiceLifecycleDialog` (built on
  `ConfirmDialog`), and a status closure banner on the detail screen. One migration
  (`20260906150000_invoice_detail_write_off_note.sql`) applied to remote DB — adds `write_off_note` to the
  `invoice_detail` read model so the bad-debt banner shows its note (void already exposed reason+note).
  `npm run check` 0 errors, ESLint clean, Prettier clean, svelte-autofixer clean.
- Verified live on Raad LTD: draft menu has no lifecycle items; issued menu offers Mark received / Write off
  / Void; mark-received → Paid + green banner; reopen → back; write-off + note → Bad debt + amber banner +
  note + client account balance drops; undo → back; void with reason+note → Voided + red banner, menu loses
  every lifecycle + Resend/Copy-link; **D2 refusal surfaces in the dialog** ("This bill still has payments on
  it, so it cannot be voided yet.") on a partially-paid invoice. Dark mode banner correct.

## Next action

**7b is done. Commit it, then ask Jafar which thread is next.** Dependency-ready now that Part 7 is
finished: **6b-2 (receipt document + receipt email from accepted payment facts)** and **Part 5 (Job / Visit /
reminder / installment handoff — also needs Jobs 11c)**. Part 8 (batch) still waits on Part 5. Part 9
(integrated journeys) waits on 2–8.

Commit: only the 7b files (migration, `src/lib/invoices/lifecycle.ts`, `src/lib/invoices/api.ts`,
`src/lib/server/validation/invoices.schema.ts`, `src/routes/api/invoices/[id]/lifecycle/+server.ts`,
`src/routes/api/invoices/[id]/+server.ts`,
`src/lib/components/invoices/InvoiceLifecycleDialog.svelte`, `src/routes/(app)/invoices/[id]/+page.svelte`)
plus Memory. The tree also carries a large pre-existing `.claude/skills/` + `.agents/skills/` diff from
before this session — never stage that.

## Notes

- Test data left on Raad LTD: invoice #4 "7b lifecycle test" (Voided — cannot be deleted by design) and
  invoice #5 "D2 refusal test" (has a $10k partial payment). Named clearly; offer Jafar a cleanup.
- Void cancellation email (contract says voiding "notifies the client through email") is NOT built — deferred
  as a small follow-up, Jafar's earlier steer. Needs a new email template/type.
- Observation for Jafar: `canCollect` still shows the "Collect payment" primary button on a bad-debt or
  marked-received invoice (its remaining balance is genuinely non-zero, so the command allows it). Pre-7b
  logic, defensible, not changed.
- Invoices list "Collected this month / Outstanding / Overdue" stat cards still render empty dashes (unwired
  read, noted since 7a) — not chased.
- 6b-1b's "no sender ready" 422 path still untested live (unchanged).

Resume command: `read memory and continue the Invoices campaign`.
