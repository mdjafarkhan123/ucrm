# Quotes: Current Checkpoint

## Goal

Build trustworthy proposals from direct creation or a Request through customer decision, deposit readiness,
Pipeline outcome, and terminal Job handoff.

## Status: Part 6 closed — all of 6A, 6B, 6C complete and browser-verified (2026-08-22)

Parts 1–5D are closed and browser-verified (see `ROADMAP.md` and `parts/05d-quote-utilities.md` for detail):
Create Similar Quote, Archive/Restore, safe Delete, the status-aware header menu, and list bulk-archive.

Part 6A (`parts/06a-deposit-schema-and-calculation.md`) shipped: `quote_version_schedule_items`,
`quote_versions.deposit_type`/`deposit_required_minor`, the extended calculation function (deposit-only and
milestone-first-installment, fixed or percentage, recalculating live with add-on selection and capped at the
total, following Jobber's live-recalculation behavior per Jafar's "We follow jobber" call), and
Publish/Revise/Create Similar all carrying the deposit shape forward. pgTAP plan 35 passed against the linked
remote project (rolled back). While rewriting `clone_quote_version_to_draft` anyway, its already-diagnosed
seq-scan bug (deferred index) was fixed too and confirmed via `EXPLAIN` — that deferred entry is now removed.
A new, narrower deferred finding was logged instead of fixed (out of 6A's scope): `preview_quote_version_totals`
/ `POST /api/quotes/[id]/preview` gate on `quotes.view` only, not `quotes.view_price`.

Part 6B (`parts/06b-deposit-configuration-and-recording.md`) is closed: database, API routes, Zod schemas,
client `api.ts` functions, extended `GET /api/quotes/[id]`, and `QuoteDepositCard.svelte` all shipped and
browser-verified end to end — deposit-only and payment-schedule configuration, publish, record, reverse,
record again, and the `sales`/`field` permission split (see the packet's "Closing verification" section for
detail). One new, out-of-scope UI bug was found while verifying and logged to
`Memory/deferred/INDEX.md` (`Quotes list page never resolves a 403 into an error state`) rather than fixed.

Part 6C (`parts/06c-readiness-gating-and-customer-deposit-display.md`) is closed: browser-verified live on
Quote #36 — the header badge showed "Deposit due" while unsatisfied and both the real `/q/{token}` customer
link and staff "Preview as client" showed the required amount with the "arrange with your contractor"
message and no payment control; recording the deposit flipped all three to "Ready for job" / a green
"Received" badge. The no-`quotes.view_price`-viewer case wasn't clicked through live (no restricted test
member exists) — Jafar accepted the pgTAP coverage plus the shared `include_money` gate as sufficient and
closed it without that live check.

## Exact next action

Part 6 is fully closed. Per `ROADMAP.md`, the next dependency-ready part is Part 7 (Quote-backed Sales
Pipeline completion), which resumes `sales-pipeline` Part 5 now that real Quote/deposit truth exists. Confirm
with Jafar before starting Part 7 — it means switching into the `sales-pipeline` campaign as the active one,
or continuing something else in `quotes` first if Jafar has other priorities.

Send as Email waits for Communications and Convert to Job waits for Jobs; neither ships as a simulated
success — both stay disabled in the menu.

## Protected work

- Keep Requests/Assessments, Sales Pipeline Parts 1-4, and Quote Parts 1-5D and 6A-6B stable.
- Never raise SQLSTATE `40001` for a business conflict; Quotes uses `P0409`.
- Database commands own money; TypeScript never recomputes persisted totals.
- Published versions, their customer snapshots, and every signature are immutable. A revision ends the
  decision, and the signature goes quiet with it - nothing is deleted.
- One builder for the customer payload, and one renderer. Never a second copy for preview, PDF, or email.
- Raw access tokens and signature object keys are returned to nobody: tokens exist once at creation, keys
  never leave the server.
- `anon` receives no Quote table/function grants; public resolution is server-only through the token hash.
- Delete only ever targets a direct-creation draft with zero non-draft version history; everything else is
  Archive.
- Communications, Payments, Pipeline outcome, and Jobs side effects stay outside Parts 5-6B.

## Required pointers

- `parts/06c-readiness-gating-and-customer-deposit-display.md` - this part's packet and open checklist item.
- `parts/06b-deposit-configuration-and-recording.md` - the closed packet, for the shipped deposit
  configuration/recording shape Part 6C builds on.
- `parts/06a-deposit-schema-and-calculation.md` - the closed packet 6B built on.
- `docs/quote-behavior-contract.md` §§ Deposits and payment schedules, Staff permissions.
