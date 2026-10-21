# New Quote concept implementation — 21 October 2026

Approved reference: `concept.pen` → Batch 34, approved A (`B5DLv`, dark `q7Cn1w`), with Batch 35's blue summary.
Status: verified in the application preview; waiting to merge into main. Public tunnel still serves main.

## What changed

- Reused `CreateFormHeader`, `RecordFormLayout`, `SectionBlock`, the existing pricing block, notes and attachments.
- Extended `AddSectionControl` with the approved optional-card presentation. Client view now describes the choices; keyboard toggling of unit prices was verified.
- Discount and tax use their existing embedded rows inside one shared RailCard; their staged save behaviour is unchanged.
- Extended `MoneyFeatureCard` with the ink-blue record summary and approved colour tokens. `ProfitCard` and
  `QuoteSummaryCard` now adapt data to that component instead of owning separate card markup. Existing record
  uses adopt the new appearance; list and client money cards keep their own approved presentation.
- Fixed shared rail cards shrinking under a constrained height and wrapped narrow-card hints. Two existing
  optional-boolean type errors in the pricing block were corrected; its non-rendered upload cleanup Set
  intentionally remains non-reactive.

## Main journey proved

Owner in Raad LTD, existing test client M5Gate Test. Saved **Quote #47**, ID
`ccdc5ea2-d95e-454c-8a8a-5ec5a3075962`, title “Design proof — shared quote form”.
One service $125, 10% discount $12.50, 10% tax $11.25, final total **$123.75**. Introduction, client message and
internal note persisted. Save showed loading and was disabled with Cancel during the request. The quote
remains a draft; no send or status-change action was taken.

Verified using the running SvelteKit app on port 5174 and the same managed database as main. No schema,
access rule, infrastructure, or calculation changes.

## Screen check

Compared with the approved Pencil screenshot at 1440; inspected empty light/dark, selected client and priced
line, optional copy sections, discount/tax dialogs, saving, missing-client error and a long title. At 390,
fixed the optional card's cramped action row and checked the form in light/dark with no page overflow
(document width and viewport both 390). Checked the shared summary on New Job, New Invoice and the saved quote.
Screenshots are in this folder. Three rounds: rail shrinking/hints; narrow optional card; final inspection.

## Checks

- `npx svelte-check --tsconfig docs/evidence/2026-10-21-new-quote-page/svelte-check.json --output human` —
  0 errors, 0 warnings (focused roots; required ambient declarations included).
- ESLint against the 10 affected Svelte components, using the repository rules with projectService disabled
  because TypeScript is checked separately — 0 errors, 0 warnings.
- Svelte MCP autofixer after SCSS preprocessing — no issues; existing pricing-editor adoption/callback effects
  were reviewed and retained because they synchronize upstream seeds and notify the owning form.
- `git diff --check` and focused Prettier check — passed.

## Known limits and next proof

This is a presentation implementation. The new-record form has a running subtotal but no server preview of
cost, profit, discount or tax totals. Its blue card shows the subtotal and explains that final figures are
worked out when saved; it does not fabricate profit. The saved quote shows the server's cost/profit figures.
Batch 35's complete job-stage/invoice-context content and a live pre-save profit preview remain unfinished.
New Invoice and New Request have not been rebuilt onto their approved full-page/shared-header designs.

Merged to main as `c10e08aa`; `/quotes/new` rechecked on the public tunnel (`public-quote-live.png`, dark mode).
Do not create another verification quote; #47 already proves the journey.
