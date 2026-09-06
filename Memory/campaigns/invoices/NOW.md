# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- **Parts 1–8 CLOSED + committed. Part 9 CLOSED 2026-09-06** — both sessions browser-verified live.
  Session A: batch create → batch deliver → client view → void. Session B: direct, recurring/period, and
  whole-job journeys + the payment/receipt journey, all verified with real (non-stubbed) side effects.
  Full evidence: `ROADMAP.md` "Part 9 Session B verification".
- **Only Part 5c remains** — progress/installment invoicing (Jobs 11c work, transferred here 2026-09-05).
  **Blocked on Jobs 11a** (payment-schedule setup). No UI exists. Gate: installments total the job, issued
  installments lock, each bills once.

## Next action

Campaign is parked. Do not start 5c until **Jobs 11a** ships. When it does, resume with
`read memory and continue the Invoices campaign` and scope 5c against `ROADMAP.md` Part 5c + the three
"facts the ledger parts established" notes in ROADMAP (esp. 3c owns the progress-invoice Void exclusion,
which needs the installment link 5c creates).

## Known deferrals — outside this campaign, do not treat as bugs

- **Billing-contact fan-out**: invoice email + receipt email send to the client's PRIMARY email only, not
  "+ billing contact" — known Jobber difference.
  `Memory/deferred/invoice-email-sends-to-primary-only-not-billing-contact.md`.
- **Void → client cancellation email**: needs a new template (7b note).
- Payment edit/delete, one-payment-across-several-invoices, Invoices-list stat cards (still "—" by design),
  and SMS delivery are all deferred outside this campaign.
- Two reminder gaps belong to **Jobs**, not here: billing "On dates we pick ourselves" and "Once, when the
  job is finished" raise no reminder until a date/closure exists — finished work can sit invisible.

## Live test-data state (Raad LTD, org 18f0d717-904e-48d8-bd99-9df7e3844cda)

- Job #2 "Recurring Lawn Care Test" stays on `fixed_per_period` (5b-3 fixture). Sept period billed as
  invoice #16 this session; Oct-31 + Nov-30 reminders pending; Aug periods → invoices #9/#10.
- Leftover drafts from Session B: #16 ($75, recurring), #17 ($200, whole job). Harmless. Delete only with
  Jafar's OK.
- Invoice #5 "D2 refusal test" carries leftover append-only test state (a $1,000 "other" payment + extra
  receipt emails). Remove only by reversal, with Jafar's OK.

## Notes

- `database.types.ts` hand-added RPCs reorder on regeneration — fine.
- Local migration filenames vs remote migration versions do not match — existing convention.
- Repo-wide CRLF drift on ~300 `src/` files — never stage it. Skill-dir edits never staged with feature commits.

Resume command: `read memory and continue the Invoices campaign` (only after Jobs 11a).
