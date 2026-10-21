# Batch 35 money card on saved job, quote and invoice pages — 2026-10-21

Pencil: `vIjf0` (Approved B). Built as `work/RecordMoneyCard.svelte` on the saved Job, Quote and Invoice
rails; it replaces `jobs/JobCostingCard` and `work/ProfitCard` (both deleted) and the invoice page's inline card.

Server figures added (migration `20261221090000_saved_record_money_card.sql`, applied with psql):
- `job_costing` now returns `labor_minutes` ("Labor · 1 h").
- `job_billing_summary` — invoiced (before tax) and still owed on a job's sent bills.
- `invoice_money_context` — billed before, this bill's share of its job, deposit applied, profit from job lines.

Live checks at 1440 as the Raad LTD owner (worktree dev server, port 5191), dark and light:
- Job #20 (open, time logged, draft invoice only): Profit so far $17,523, labor 1 h $27, unrated-hours note;
  no Invoiced row because its only bill is a draft. `job-20-light.jpg`.
- Job #14 (closed, two draft bills): Final profit $707 · 81% margin, item cost $170; no Invoiced row.
- Job #18 (three sent bills, all paid): Invoiced $665 of $665; no Still owed (DB confirms each bill fully applied).
- Invoice #22 (stage bill of Job #18): Balance due $0.00, 100% paid, "$300 invoice, less $300 paid", Billed before
  $365 (55%) / This invoice · final $300 (45%), client account balance kept. Matches `tNlft` colours.
- Quote #41: Estimated profit $200, Client pays with Sales tax $220.00, Deposit on approval · 25% $55.00.
  `quote-41-light.jpg`.

Not checked live: the no-cost-access versions (code mirrors `DraftMoneyCard`); a bill with a deposit applied.
`svelte-check`: no errors in the changed files (two older errors elsewhere, untouched).
