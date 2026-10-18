# C4 — Job details in the concept

**Campaign:** contractor-design-concept · **Plan:** `docs/contractor-design-concept-behavior-contract.md` § First version 2
**Stage:** Drawn 2026-10-18; waiting for Jafar's review. Frame "Concept · Job details · Owner · 1440"
(`hdOUv`, x 7289, y 0) in `concept.pen`.
**Live page:** `src/routes/(app)/jobs/[id=uuid]/+page.svelte` (checklist row in `stages/list-2a-daily.md`, Pencil 🟡).
**Done when:** Jafar approves the frame; his yes and the date are recorded here.

## Research (what Jobber shows on a job)

- Header: status pill, type icon, history, More, **one green action that changes with status** (booking
  confirmation, go to visits, create invoice, re-open); title with pencil; client card left, facts right
  (`.claude/skills/jobber/jobber-08-screen-patterns.md`; https://help.getjobber.com/en/articles/jobs-in-the-jobber-app/).
- Job costing: a **profit bar** — total price, line item cost, labour, expenses, profit and margin; "costs so far"
  while open; only staff with costing rights see it (https://help.getjobber.com/en/articles/job-costing/).

## What is drawn (every live block kept; layout new)

- Header card: job tile, status, meta, history, More, green "Create invoice"; title + pencil; client box (call,
  text, email, menu) beside the facts; Request → Quote → Job → Invoice → Paid strip at its foot.
- Main column: Visits (today's row in the Schedule colour with Start timer; Past folded) → Instructions →
  Products and services with subtotal, discount, tax and total at its foot → Labor → Expenses → Checklists.
- Rail: green Job total card with the profit bar (team only) → Billing with payment schedule and invoice
  reminders → Notes → Photos and files → Signatures → Work report. History still swaps the rail (not drawn).

## Asked with the drawing (default: keep as drawn)

1. Green main button changing with status (live has none; "Create invoice" sits in More).
2. Job total and costing in one green card; discount and tax in the products card's foot.
3. Billing and invoice reminders in one card. 4. Instructions moved beside Visits.

## Next

Jafar saves `concept.pen` (Ctrl+S), reviews; then commit the `.pen` alone and record approval.
