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

- Header card: job tile, status, meta, history, More, green main button; title + pencil; client box (call,
  text, email, menu) beside the facts; Request → Quote → Job → Invoice → Paid strip at its foot.
- Main column: Visits (today's row in the Schedule colour with Start timer and the visit's own instructions, as
  live shows them; Past folded) → Instructions (job-wide) → Products and services (pink tile: priced on the quote)
  with subtotal, discount, tax and total → **Billing** (facts, payment schedule, invoice reminders list) → Labor →
  Expenses → Checklists.
- Rail: green Job total card with the profit bar (team only) → Notes → Photos and files → Signatures → Work
  report. History still swaps the rail (not drawn).

## Jafar's answers (2026-10-18 review)

1. Green main button that changes with status: **keep**.
2. Job total card: **keep**, but the bar looked plain → now meaningful colours (items pink, labour time,
   expenses light blue, profit white; tokens `color-feature-items/-labor/-expenses`, in `colors.md`).
3. Billing: Jobber keeps it in the main area and reminders can grow → **moved to the main column** after
   Products. Instructions: the app already has job-wide and per-visit instructions (like Jobber); visit rows now
   show their own line.
4. Section title line: **everywhere** → added to Home and Jobs list cards; rule in `cards.md`.
5. Products and services "looked plain" → each line has a 40 thumb (the line's photo; a service gets a job
   tile), a Product (quote pink) or Service (job green) pill from the line's category, a tinted table head, a
   line count, and totals in a subtle panel with a white Total box. Jafar: "now looks better".
6. Discount and tax editing: Jafar chose "what is better" → Jobber's way. The read view shows the numbers
   only (small pencils removed); the card's Edit opens one edit mode for lines, discount and tax with one
   Cancel / Save (frame `jFBRB`). **Behaviour change for the build:** today discount and tax save on their own
   from rail cards (`RecordDiscountCard`, `RecordTaxCard`); they move into the products edit mode. Every live
   field is kept (client-facing name, % or $, tax source incl. custom rate and "save as reusable rate").
7. Plain icon tiles: **yes, recolour, his review** → Notes conversation teal, Checklists time (filled in on
   visits). Photos and files stays the Files grey (map); Signatures stays success.

## Review list (2026-10-18)

Item 1 done: Jafar chose **one page, no tabs** (tab drafts deleted; he found the underline tabs not premium).
Main column is now Visits → Instructions → Checklists → "Money" divider → Products → Billing → Labor →
Expenses. Still waiting for his pick: 2 neutral avatars, 3 amber "Required · N left" checklist pill, 4 receipt
photo on expenses, 5 no box-in-box in Signatures, 6 Instructions hint wording, 7 orphan line count; and the
right column staying in view on scroll (behaviour).

Section titles bigger (Jafar): every section card title is now 20/600 (`font-size-larger`, -0.2) with a 40
tile (20 icon), also in the edit drawing. Asked whether Home and Jobs list follow; then update `typography.md`.
Note: code `--typography--fontSize-large` is 15px but Pencil `font-size-large` is 16.

## Next

Jafar reviews the changes above (frame `hdOUv`, edit mode `jFBRB`, Home `rKrbu`, Jobs list `t8ULdJ`). On his yes, record approval
and date here, set C4 approved in NOW and the roadmap.
