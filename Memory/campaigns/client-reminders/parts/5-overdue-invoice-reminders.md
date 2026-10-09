# 5 — Overdue invoice reminders

**Campaign:** client-reminders · **Plan:** `docs/client-reminders-behavior-contract.md` § Overdue invoice reminders, § Customer messages: shared rules
**Code:** worktree `/home/jafar/Ucrm-cr5`, branch `client-reminders-part5`
**Done when:** An invoice 1 day overdue gets its reminder after 8 am; paying it stops the second.

## Design (technical, chosen 2026-10-09; mirrors Part 3)

- New trigger `invoice.past_due` (subject `invoice`, database subject type `invoice`, source `invoices`), config
  `{ days_after_due: 1–90 }`. Preset "Overdue invoice reminders": trigger 1 day after, email, wait 6 days, email.
  Validator: an invoice recipe has at most 2 emails, and trigger days + waited days ≤ 90.
- `public.emit_due_invoice_reminders(limit)` runs each wake: per active recipe, receivable invoices whose
  reminder time (local `due_date + days` at 08:00) has arrived, still past due, reminder time after both
  `issued_at` and the version's `activated_at`. Event `occurred_at` = reminder time, so the wait lands at 8 am
  too. Source id from recipe + `root_invoice_id`: a replacement bill never restarts the reminders.
- Stops: invoice paid, marked received, voided, written off or replaced; client removed; `invoice_reminders`
  switch off; Do not disturb. Action `action.send_invoice_email` (variables: customer, business, invoice
  number, balance, due date, pay link). The worker mints a fresh invoice link (primary + billing contact, like
  "Send invoice") without revoking earlier links.

## Steps

- [ ] Migration written (not applied)
- [ ] Catalog, validator, email variables, preset, worker, builder trigger timing, summary, client switch status
- [ ] Unit tests; `npm run check`
- [ ] Apply migration (outcome check: `select version from supabase_migrations.schema_migrations where version = '<version>'`)
- [ ] Prove on the live app; merge to `main`; remove worktree

## Next

Write the migration in the worktree.
