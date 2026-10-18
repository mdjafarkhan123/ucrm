# C4 — Job details in the concept

**Campaign:** contractor-design-concept · **Plan:** `docs/contractor-design-concept-behavior-contract.md` § First version 2
**Stage:** Reviewed with Jafar 2026-10-18 and redrawn; waiting for his approval. Frames in `concept.pen`:
Job details `hdOUv`, edit mode "Editing products and services" `jFBRB`.
**Live page:** `src/routes/(app)/jobs/[id=uuid]/+page.svelte`. **Done when:** Jafar approves; record his yes and date here.

## Research

Jobber job page: one green action that changes with status; client card left, facts right; one scrolling page;
job costing profit bar for staff with costing rights (`.claude/skills/jobber/jobber-08-screen-patterns.md`,
https://help.getjobber.com/en/articles/job-costing/). Line items end in Subtotal, Discount, Tax, Total; edit is
section-scoped (`jobber-03-quotes.md` § Edit state).

## What is drawn (decided with Jafar 2026-10-18)

- Header card with the changing green main button, client box, facts, Request → Paid strip.
- One page, no tabs (he found tabs not premium): Visits (visit rows show their own instructions) →
  Instructions → Checklists → "Money" divider → Products and services → Billing (main column: facts,
  payment schedule, reminders list) → Labor → Expenses.
- Rail: Job total card with a coloured profit bar (`color-feature-items/-labor/-expenses`, profit white) →
  Notes → Photos and files → Signatures → Work report.
- Products: 40 photo thumbs (service: job wrench tile), Product (quote pink) / Service (job green) pills,
  tinted table head, subtle totals panel with a white Total box; no small pencils.
- **Behaviour change for the build:** the card's Edit opens one edit mode for lines, discount and tax with one
  Save (`jFBRB`); today discount and tax save alone from `RecordDiscountCard` / `RecordTaxCard`. All live
  fields kept.
- Tiles: Notes conversation, Checklists time, Products quote. Code `--typography--fontSize-large` is 15px vs
  Pencil 16.

## Answers 2026-10-18 (second review)

- Right column: same as the live app, it scrolls with the page (`RecordDetailLayout` has no sticky rail).
- Titles everywhere through one shared part: Pencil component **Card header** `hHVVU` (Parts board, "Card header
  row") now drives every card header on Job details, the edit frame, Home `rKrbu` and Jobs list `t8ULdJ`
  (Jobs list headers gained tiles). Rule in `cards.md`, `typography.md`.
  **Build:** one shared CardHeader in code replaces the separate Card / RailCard / SectionBlock headers.
- Small fixes drawn on a separate copy for comparison: **`tNdkX` "Small fixes (compare)"** beside `hdOUv`
  (edit frame `jFBRB` moved under `hdOUv`): grey avatars, amber "Required · 3 left" pill, receipt photo on
  expenses, no box in Signatures, Instructions hint "The crew sees these on every visit", line count moved
  into the Products hint.

## Next

1. Jafar compares `hdOUv` with `tNdkX` and says which fixes to keep. Keep the chosen ones in `hdOUv`, delete
   `tNdkX`, ask him to save (Ctrl+S), commit `concept.pen`.
2. On his yes for Job details, record approval here and in NOW/ROADMAP.
3. Next screen **New job**: one form (title, client + property, Products edit block `jFBRB`, Visits edit with
   one-off/recurring, Billing reminder, Job total, Cancel / Save job). Live: `src/routes/(app)/jobs/new/
   +page.svelte` → `src/lib/components/jobs/JobForm.svelte`. Research Jobber's New job first.
