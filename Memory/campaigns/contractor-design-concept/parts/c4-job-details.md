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
- Section titles 20/600 (`font-size-larger`, -0.2) with 40 tiles; title line under every card header
  (also on Home `rKrbu` and Jobs list `t8ULdJ`; rule in `cards.md`).
- Tiles: Notes conversation, Checklists time, Products quote. Code `--typography--fontSize-large` is 15px vs
  Pencil 16.

## Next

Paused 2026-10-18 by Jafar.
1. If `git status` shows `concept.pen` modified, commit it (later edits land once Jafar saves in Pencil).
2. Ask, as left: "Should Home and the Jobs list get the same bigger titles and icons?"; which review points to
   do (2 neutral avatars, 3 amber "Required · N left" checklist pill, 4 receipt photo on expenses, 5 no
   box-in-box in Signatures, 6 Instructions hint "The crew sees these on every visit", 7 orphan line count);
   and whether the right column stays in view on scroll.
3. On his yes, record approval here and in NOW/ROADMAP; update `typography.md` if titles go app-wide.
4. Next screen **New job**: one form (title, client + property, Products edit block `jFBRB`, Visits edit with
   one-off/recurring, Billing reminder, Job total, Cancel / Save job). Live: `src/routes/(app)/jobs/new/
   +page.svelte` → `src/lib/components/jobs/JobForm.svelte`. Research Jobber's New job first.
