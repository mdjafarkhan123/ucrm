# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- Parts 1–4, 5a, 5b-1, 5b-2, 5b-3, **5b-4**, 6a, 6b-1, 6b-2, 6c, 7a, 7b closed and committed.
- **5b-4 CLOSED 2026-09-06** — browser-verified, committed `9fdc7ca`. Roadmap entry has the detail.

## Next action

No part is in progress. Await Jafar's pick of the next thread. Dependency-ready options:

- **5b-5** — Ready-to-bill queue: one cross-client list of work requiring invoicing. Scale-sensitive,
  so it needs the `performance-review` design branch before implementation.
- **5c** — Jobs 11c payment-schedule installments + progress invoicing from an installment
  (depends on 5a + Jobs 11a).
- **Part 8** — batch create + batch deliver (depends on Parts 5–7, all now closed).

Read `ROADMAP.md` for the transition once Jafar picks.

## Test data left on the dev app (Raad LTD) from 5b-4 verification

- Job **#10** "5b-4 Per-Visit Verify" (Tester Account): recurring, per-visit / after-each-completed-visit,
  two completed visits (Aug 9 + Aug 16, 2026), one $50 "Lawn mowing" line. One open per-visit reminder
  (Aug 9, "later"). Keep or delete — no other part reads it.
- Invoice **#11** ($50 draft, Job #10, Aug 16 visit) — the "Invoice now" check. Delete if clean data matters.

## Open items Jafar has not decided (carried from 5b-4)

- Whether the prompt should also fire for a one-off job right after "Finish job" (Jobber's mobile app does;
  our contract calls it "a separate answer"). Today that path auto-creates the on_completion reminder and
  "Create invoice" is one click away. Flagged, not built.
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
- Verification drafts nobody needs: invoice **#6** ($66,500, Job #1), **#7** ($150, 5b-1), **#8** ($75,
  5b-2 visit), **#9** ($75, 5b-3 period), **#10** ($75, the fix's live check). Delete any if clean data matters.
- Job **#2** ("Recurring Lawn Care Test", Tester Account): fixed-per-period / month-end. Keep it on
  `fixed_per_period` — 5b-3's period tests read it.

## Notes

- `database.types.ts`: the two 5a RPCs were hand-added; a later regeneration will reorder them — fine.
- Local migration filenames and remote migration versions do not match — existing convention.
- Repo-wide CRLF drift on ~300 `src/` files — unrelated, never stage it. `.env` is CRLF too.
- Skill-dir edits (`.claude/`, `.agents/`, `.codex/`, `.opencode/`) are never staged with feature commits.
- Component `.svelte.spec.ts` tests need a Playwright browser this environment lacks (15 test files skip);
  `npm run test:unit` still runs 1723 node tests. Browser-verify UI in the real app instead.
- Deferred: payment edit/delete, void→client cancellation email, bulk payment across invoices, Invoices list
  stat cards unwired.

Resume command: `read memory and continue the Invoices campaign`.
