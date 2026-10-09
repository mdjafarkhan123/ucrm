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

- [x] Migration `20261115090000_invoice_reminders.sql` written on the branch
- [x] Catalog, validator, email variables, preset, worker, builder trigger timing, summary, client switch status
- [x] Unit tests; `npm run check` clean (on the branch)
- [x] Apply migration `20261115090000` (all applied and recorded 2026-10-09) in three repeatable transactions via MCP `execute_sql` (Part 4's method;
  no `apply_migration`, it stamps today's version). The file's sections map to them:
  - [x] A — §1–3 (constraints, helpers, `emit_due_invoice_reminders`): applied 2026-10-09.
    Check: `select to_regproc('public.emit_due_invoice_reminders')` is not null.
  - [x] B — §4 (`intake_automation_events`, `advance_automation_work_item`; file lines ~197–705).
    Check: `select prosrc like '%action_due_invoice_email%' from pg_proc where proname = 'advance_automation_work_item'`.
  - [x] C — §5 (email functions) plus `insert into supabase_migrations.schema_migrations (version, name) values
    ('20261115090000', 'invoice_reminders')`. Check: `select to_regproc('public.perform_automation_invoice_email_effect')`
    and `select version from supabase_migrations.schema_migrations where version = '20261115090000'`.
- [ ] Regenerate `database.types.ts`; EXPLAIN `emit_due_invoice_reminders`
- [ ] Prove on the live app (preset turns on; builder "Days after the due date" field; client switch "Not
  sending" line; an invoice due yesterday gets one email after 8 am; paying stops the second); design screen
  check; merge to `main`; remove worktree

## Next

Regenerate `database.types.ts` in the worktree (MCP `generate_typescript_types`), EXPLAIN
`emit_due_invoice_reminders`, then the live proof. Worktree `.env` is a copy of the main one (ignored).
