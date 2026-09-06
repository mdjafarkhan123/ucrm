# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- Parts 1–4, 5a, 5b-1…5b-5, 6a, 6b-1, 6b-2, 6c, 7a, 7b, **8a** closed.
- **8a (batch create) closed + committed 9f0ae89 on 2026-09-06.** Jafar's two 8a rulings:
  both "follow Jobber" — no batch-specific line cap (app's existing 100-lines/invoice rule stays),
  and the 25-job batch cap stays as our one measured deviation (Jobber states no limit; unbounded is
  unverified at scale, lift later only with a perf pass).

## Next action

**Scope 8b — batch deliver.** Nothing is scoped yet. Propose the part (behavior, acceptance, risks) and get
Jafar's approval before building. It must reckon with the org email allowance and the 20-per-5-min send rate
limit (see "Carried over"). Roadmap 8b: select draft/awaiting/past-due invoices → issue + queue emails; drafts
issue on send; each email queued once; paid invoices ineligible. Jobber grounding is in
`.claude/skills/jobber/jobber-05-invoices-payments.md` "Batch invoicing — 2026-09-06" (Batch Mailer: method
first, then list by status, PDF opt-in, client-hub click-through).

## Open items Jafar has not decided

- **Two reminder gaps, flagged in 5b-5, owned by the Jobs campaign, not fixed:** billing set to "On dates we
  pick ourselves" raises no reminder until somebody adds a date, and "Once, when the job is finished" raises
  none until the job is actually closed. Finished work can sit invisible in both cases.
- Whether the invoice-now prompt should also fire for a one-off job right after "Finish job" (Jobber's
  mobile app does). Flagged in 5b-4, not built.
- Job #2's Sep-30 and Oct-31 month-end reminders are still marked `resolved/invoiced` with no invoice
  behind them — old 5b-2 bug on test data only. Offered to reset; awaiting Jafar's word. Nov-30 is fine.

## 5a deferrals (decided, not bugs)

- Mixed-property selections are **refused** in the 5a picker (tax rates can differ); 8a's grouping splits them.
- Applying an existing quote **deposit** at creation is still UI-only to build (`apply_client_payment` exists).

## Carried over (pre-existing, app-wide)

- Not-found records sit on a loading skeleton forever (`/payments/<bad id>`, `/invoices/<bad id>`).
- Raad LTD sender display name is "Staff Jafar"; should be the business name — contractor-side fix in
  Settings → Communications → Email.
- Raad LTD email allowance is a manual Unlimited override, not a package entitlement — proper fix belongs to
  **communications-activation** (Paused). 8b must reckon with allowance + the 20-per-5-min send rate limit.
- Leftover test data on invoice #5 "D2 refusal test": a $1,000 "other" payment + two extra receipt emails to
  `info.hiddenknowledge@gmail.com`. Append-only history — remove only by reversal, with Jafar's OK.
- Verification drafts nobody needs: invoices **#6–#13**. Ready-to-bill queue was empty after 8a verify —
  a fresh 8b test needs new draft/awaiting/past-due invoices.
- Job **#10** gained a completed visit ("8a batch verify visit", Sep 4) and invoice **#13** is a real draft —
  8a's evidence, safe to delete.
- Job **#2** ("Recurring Lawn Care Test", Tester Account): keep it on `fixed_per_period` — 5b-3's tests read it.

## Notes

- `database.types.ts`: hand-added RPCs (5a/5b-5, and now 8a's) will reorder on a later regeneration — fine.
- Local migration filenames and remote migration versions do not match — existing convention.
- Repo-wide CRLF drift on ~300 `src/` files — unrelated, never stage it. `.env` is CRLF too.
- Skill-dir edits (`.claude/`, `.agents/`, `.codex/`, `.opencode/`) are never staged with feature commits.
- Component `.svelte.spec.ts` tests need a Playwright browser this environment lacks; `npm run test:unit`
  still runs 1783 node tests. Browser-verify UI in the real app instead.
- Deferred: payment edit/delete, void→client cancellation email, bulk payment across invoices, Invoices list
  stat cards unwired.

Resume command: `read memory and continue the Invoices campaign`.
