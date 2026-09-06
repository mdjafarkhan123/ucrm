# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- **6b-2b CLOSED + committed** — payment detail screen `/(app)/payments/[id]`, its receipt print page,
  `payment_detail` + `payment_receipt_preview`, and invoice financial-history rows linking to a payment.
  Browser-verified. Part 6b (receipts) is now finished end to end.
- Part 7 and 6b-2a closed earlier (7a `d5a0250`, 7b `d324946`, 6b-2a `e1cf299`).

## Next action — ask Jafar which thread to open

Dependency-ready parts, none started: **Part 5** (Job/Visit/reminder/installment handoff — also needs Jobs
11c), **Part 8** (batch create + batch deliver), **Part 9** (integrated journeys + measured performance).
Read `ROADMAP.md` only once he picks. Follow the Working Procedure: state understanding, inspect the
relevant files, present the plan, wait for approval.

## Known issues (not blockers)

- **Not-found records sit on a skeleton forever.** `/payments/<bad id>` and `/invoices/<bad id>` both keep
  showing the loading skeleton instead of the error state after a 404. Pre-existing app-wide behavior, not
  introduced by 6b-2b; worth a small fix in whatever part next touches detail-page loading.
- **Raad LTD sender display name is "Staff Jafar"** on `hello@test.upliftcontractor.com`, so client-facing
  invoice/receipt email shows that as the From name. Should be the business name per Jobber. Fix is
  contractor-side: Settings → Communications → Email → edit that sender. Not done.
- **Email allowance for Raad LTD is a manual override**, not a package entitlement — Jafar added an Unlimited
  exception on 2026-09-05 (jafar → Organizations → Raad LTD → Email allowance authority). The proper
  package-entitlement fix belongs to **communications-activation** (Paused).
- **Leftover test data on invoice #5 "D2 refusal test" (Raad LTD)**: a $1,000 "other" payment (ref "6b-2a
  receipt browser test"), plus **two extra receipt emails** sent to the test client
  `info.hiddenknowledge@gmail.com` during 6b-2b verification. `client_payment_events` /
  `invoice_payment_allocations` are append-only (trigger `payment_history_is_append_only`), so the payment
  cannot be plain-deleted — remove it only with Jafar's OK or via a proper reversal.

## Notes

- `database.types.ts`: regenerate with the Supabase MCP tool, then `npx prettier --write` it — that collapses
  the whole-file reformat to just the real schema delta. No `supabase login` needed.
- Local migration filenames and remote migration versions do not match (remote assigns its own timestamps);
  that is the existing convention here, not drift.
- The email worker now drains on its own within seconds — a queued send really goes out. Manual drain if
  needed: `POST http://localhost:5173/api/internal/communications/email-worker` with
  `authorization: Bearer $COMMUNICATIONS_WORKER_SECRET`.
- Repo-wide CRLF drift on ~300 `src/` files + migration files nobody touched — unrelated, never stage it.
  `.env` is also CRLF: strip `\r` when reading secrets in a shell.
- Skill-dir edits (`.claude/`, `.agents/`, `.codex/`, `.opencode/`) are never staged with feature commits.
- `npm run test:unit` leaves 15 files unrun — Playwright's browser binary is not installed on this machine.
- Deferred: payment edit/delete, void→client cancellation email (needs template), bulk payment across several
  invoices, Invoices list stat cards still unwired.

Resume command: `read memory and continue the Invoices campaign`.
