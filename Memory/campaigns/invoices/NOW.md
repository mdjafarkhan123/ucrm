# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- Parts 1–4, 5a, 5b-1…5b-5, 6a, 6b-1, 6b-2, 6c, 7a, 7b closed.
- **5b-5 CLOSED 2026-09-06** — ready-to-bill queue, browser-verified. Roadmap has the detail and the
  measured performance evidence.

## Next action

No part is in progress. Await Jafar's pick of the next thread. Dependency-ready options:

- **5c** — Jobs 11c payment-schedule installments + progress invoicing from an installment
  (depends on 5a + Jobs 11a).
- **Part 8** — batch create + batch deliver (depends on Parts 5–7, all now closed). The ready-to-bill
  queue is the screen batch selection belongs on; it was built without checkboxes on purpose.

Read `ROADMAP.md` for the transition once Jafar picks.

## Open items Jafar has not decided

- **Two reminder gaps, flagged in 5b-5, owned by the Jobs campaign, not fixed:** billing set to "On dates we
  pick ourselves" raises no reminder until somebody adds a date, and "Once, when the job is finished" raises
  none until the job is actually closed. Finished work can sit invisible in both cases. Fixing either means
  changing the job billing card, which 5b-5 was not authorized to touch.
- Whether the invoice-now prompt should also fire for a one-off job right after "Finish job" (Jobber's
  mobile app does). Flagged in 5b-4, not built.
- Job #2's Sep-30 and Oct-31 month-end reminders are still marked `resolved/invoiced` with no invoice
  behind them — old 5b-2 bug on test data only. Offered to reset; awaiting Jafar's word. Nov-30 is fine.

## 5a deferrals (decided, not bugs — carry into later 5b/8 parts)

- Mixed-property selections are **refused** in the picker (tax rates can differ); splitting belongs to Part 8.
- Applying an existing quote **deposit** at creation is still UI-only to build (`apply_client_payment` exists).

## Carried over (pre-existing, app-wide)

- Not-found records sit on a loading skeleton forever (`/payments/<bad id>`, `/invoices/<bad id>`).
- Raad LTD sender display name is "Staff Jafar"; should be the business name — contractor-side fix in
  Settings → Communications → Email.
- Raad LTD email allowance is a manual Unlimited override, not a package entitlement — proper fix belongs to
  **communications-activation** (Paused).
- Leftover test data on invoice #5 "D2 refusal test": a $1,000 "other" payment + two extra receipt emails to
  `info.hiddenknowledge@gmail.com`. Append-only history — remove only by reversal, with Jafar's OK.
- Verification drafts nobody needs: invoices **#6–#12**. **#12** ($275, job #11) and job **#11**
  "5b-5 Whole Job Queue Check" (Tester Account, one-off, closed) are 5b-5's; delete both if clean data
  matters. Job **#10** "5b-4 Per-Visit Verify" still has one unbilled visit and is the only row the queue
  shows today — keep it if you want something in that list.
- Job **#2** ("Recurring Lawn Care Test", Tester Account): fixed-per-period / month-end. Keep it on
  `fixed_per_period` — 5b-3's period tests read it.

## Notes

- `database.types.ts`: the 5a RPCs and 5b-5's two were hand-added; a later regeneration will reorder them — fine.
- Local migration filenames and remote migration versions do not match — existing convention.
- Repo-wide CRLF drift on ~300 `src/` files — unrelated, never stage it. `.env` is CRLF too.
- Skill-dir edits (`.claude/`, `.agents/`, `.codex/`, `.opencode/`) are never staged with feature commits.
- Component `.svelte.spec.ts` tests need a Playwright browser this environment lacks (15 test files skip);
  `npm run test:unit` still runs 1723 node tests. Browser-verify UI in the real app instead.
- Deferred: payment edit/delete, void→client cancellation email, bulk payment across invoices, Invoices list
  stat cards unwired.

Resume command: `read memory and continue the Invoices campaign`.
