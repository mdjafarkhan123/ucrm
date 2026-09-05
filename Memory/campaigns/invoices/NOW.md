# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- Active part: none. **3c CLOSED 2026-09-05** (60/60 pgTAP, index plans measured). Awaiting Jafar's pick of
  the next part.

## Exact next action

Two things wait on Jafar:

1. **Commit 3c.** The migration `supabase/migrations/20260905130000_invoice_source_claims_and_chains.sql` and
   the test `supabase/tests/database/invoices_source_claims_and_chains.sql` are verified but still untracked in
   Git. Commit only when Jafar says so. (The test needed four fixes this session: `bill` view no longer selects
   `total_minor`; the rebill-total assertion reads through `public.invoice_money`; a new `original` chain-root
   view disambiguates `subject` lookups once a successor copies the subject; `replace_invoice_lines` called with
   its real 4-arg signature. The migration itself was correct as applied.)
2. **Pick the next part.** Dependency-ready now that 3a–3c are done: Part 4 (direct Invoice list/new form/detail),
   then Part 5 (Job/Visit/reminder/installment handoff, also needs Jobs 11c). Part 4 has no outside dependency.

## Blockers and non-obvious risks

- Remote migration versions are assigned by the MCP tool and do not match local filenames, so `supabase db push`
  would replay everything. Always apply through `mcp__supabase__apply_migration`.
- No local Postgres / no `pg`: run pgTAP by pasting the whole test file into `mcp__supabase__execute_sql` in one
  call (it begins/ends with its own begin/rollback). `execute_sql` shows only the last statement's rows.
- `authenticated` has column-level SELECT on `invoices`, and money columns (`total_minor`, `subtotal_minor`,
  `tax_minor`, `discount_minor`) are deliberately excluded — amounts come back through `public.invoice_money`,
  gated on `invoices.view_price`. Tests and UI must read totals that way, never off the table.

## Essential pointers

- `docs/invoice-behavior-contract.md` — D1–D5 approved behavior
- `docs/invoice-part-2-design.md` — Part 2 design (source claims and D1–D5 commands)
- `Memory/campaigns/invoices/ROADMAP.md` — read only to select/plan the next part

Resume command: `read memory and continue the Invoices campaign`.
