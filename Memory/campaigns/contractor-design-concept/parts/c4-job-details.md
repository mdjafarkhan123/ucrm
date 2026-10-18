# C4 — Job details in the concept

**Campaign:** contractor-design-concept · **Plan:** `docs/contractor-design-concept-behavior-contract.md` § First version 2
**Stage:** Reviewed twice 2026-10-18; waiting for approval. Frames: `hdOUv` (original), `tNdkX` (proposal),
edit mode `jFBRB`.
**Live page:** `src/routes/(app)/jobs/[id=uuid]/+page.svelte`. **Done when:** Jafar approves; record his yes and date here.

## Research

Jobber job page: one green action that changes with status; client card left, facts right; one scrolling page;
job costing profit bar for staff with costing rights (`.claude/skills/jobber/jobber-08-screen-patterns.md`,
https://help.getjobber.com/en/articles/job-costing/). Edit is section-scoped (`jobber-03-quotes.md` § Edit state).

## What is drawn (decided with Jafar 2026-10-18)

- Header card with the changing green main button, client box, facts, Request → Paid strip.
- One page, no tabs: Visits →
  Instructions → Checklists → "Money" divider → Products and services → Billing (main column: facts,
  payment schedule, reminders list) → Labor → Expenses.
- Rail: Job total card with a coloured profit bar (`color-feature-items/-labor/-expenses`, profit white) →
  Notes → Photos and files → Signatures → Work report.
- Products: 40 photo thumbs, Product / Service pills, tinted table head, totals panel with a white Total box.
- **Behaviour change for the build:** the card's Edit opens one edit mode for lines, discount and tax with one
  Save (`jFBRB`); today discount and tax save alone from `RecordDiscountCard` / `RecordTaxCard`. All live
  fields kept.

## Answers 2026-10-18 (second review)

- Right column: same as the live app, it scrolls with the page (`RecordDetailLayout` has no sticky rail).
- Titles everywhere through one shared part: Pencil component **Card header** `hHVVU` (Parts board, "Card header
  row") now drives every card header on Job details, the edit frame, Home `rKrbu` and Jobs list `t8ULdJ`
  (Jobs list headers gained tiles). Rule in `cards.md`, `typography.md`.
  **Build:** one shared CardHeader in code replaces the separate Card / RailCard / SectionBlock headers.
- Small fixes on a compare copy **`tNdkX`** beside `hdOUv` (edit frame `jFBRB` moved below): grey avatars, amber "Required · 3 left" pill, receipt photo on
  expenses, no box in Signatures, Instructions hint "The crew sees these on every visit", line count moved
  into the Products hint. Jafar: "looks good" (keep all six).
- Header improved on `tNdkX` too (Jafar asked, 2026-10-18): "Job #1042" only in the top line; client box has a
  48 avatar, a client-coloured "Job address" panel with a Directions button (opens Google Maps; no map picture,
  it needs a maps service) and a quiet phone/email row; facts box 2×2: Type, Created, Started, From (pink
  "Quote #318 ↗" link pill).

## Next

1. Jafar compares the header on `tNdkX` with `hdOUv`. On his yes, `tNdkX` becomes the Job details drawing:
   delete `hdOUv`, drop "(compare)" from the name, ask him to save (Ctrl+S), commit `concept.pen`.
2. On his yes for Job details, record approval here and in NOW/ROADMAP.
3. Next screen **New job**: one form (title, client + property, Products edit block `jFBRB`, Visits edit with
   one-off/recurring, Billing reminder, Job total, Cancel / Save job). Live: `src/routes/(app)/jobs/new/
   +page.svelte` → `src/lib/components/jobs/JobForm.svelte`. Research Jobber's New job first.
