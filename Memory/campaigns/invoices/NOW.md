# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- **All build parts CLOSED + committed.** Parts 1–7, 8a, and **8b (batch deliver, committed a4d057b
  2026-09-06)** are done. Only **Part 9** — verify integrated billing journeys + measured performance —
  remains, and it is **Planned/unscoped**.

## Next action

Scope Part 9 with Jafar, then execute it. Part 9's gate (ROADMAP): the direct, Job, recurring, progress,
delivery, payment, exception, and batch journeys each pass end to end, with performance measured where a
path's cost grows. Present a short scoped plan (which journeys, what evidence) before implementing.

## Known deferrals that Part 9 must not treat as bugs

- **Billing-contact fan-out**: invoice email sends to the client's PRIMARY email only, not billing contacts
  — a known Jobber difference. `Memory/deferred/invoice-email-sends-to-primary-only-not-billing-contact.md`.
- **Void → client cancellation email**: needs a new template; deferred (7b note).
- Payment edit/delete, bulk payment across invoices, Invoices-list stat cards (still "—"), the void→client
  email, and SMS delivery are all deferred outside this campaign.

## Live test-data notes (Raad LTD, org 18f0d717-904e-48d8-bd99-9df7e3844cda) — decide before journey tests

- Job #2 ("Recurring Lawn Care Test", Tester Account): its Sep-30 / Oct-31 month-end reminders show
  resolved/invoiced with NO invoice behind them (old 5b-2 bug on test data; Nov-30 is fine). Offered to
  reset; **awaiting Jafar's word**. Keep Job #2 on `fixed_per_period` — 5b-3 tests read it.
- Invoice #5 "D2 refusal test" carries leftover test state: a $1,000 "other" payment + two extra receipt
  emails to `info.hiddenknowledge@gmail.com`. Append-only history — remove only by reversal, with Jafar's OK.
- Deliverable send queue as of 8b verify: invoices #6–#13 (drafts) + #5 (past due) = 9 eligible; #4 voided,
  #1 paid, both correctly excluded.

## Notes

- `database.types.ts` hand-added RPCs (5a/5b-5/8a/8b) reorder on a later regeneration — fine.
- Local migration filenames vs remote migration versions do not match — existing convention.
- Repo-wide CRLF drift on ~300 `src/` files — never stage it. Skill-dir edits never staged with feature commits.
- Two 5b-5 reminder gaps belong to **Jobs**, not here: "On dates we pick ourselves" and "Once, when the job
  is finished" raise no reminder until a date/closure exists — finished work can sit invisible.

Resume command: `read memory and continue the Invoices campaign`.
