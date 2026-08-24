# Part 4 - Professional proposals and immutable versions

## Outcome

Authorized staff can prepare a professional draft with customer choices, exact Discount and Tax, approved
customer-facing sections, and visibility controls. Database-owned calculation stays authoritative, and the
freeze/clone foundation can preserve every future published proposal without rewriting history.

## Approved boundary (2026-08-20)

- Match Jobber's distinct optional add-ons and up-to-three Good/Better/Best packages.
- Ship Introduction, Client message, Contract disclaimer, and customer-visible attachments/images.
- Keep warranty and extra terms inside Contract disclaimer until separately approved.
- Defer reusable Quote/package templates until the proposal model is stable.
- Build and test immutable freeze/clone machinery here. Part 5 owns the first staff publication controls:
  Send and Mark awaiting response.
- Discount is one named fixed or percentage Quote-level value. Tax is one named exclusive rate or No tax.
- Deposit and payment schedule remain Part 6. Saved Tax settings remain separately gated.

## Architecture decisions before SQL

- Extend the existing `quote_versions` draft snapshot; published rows use the same shape and become guarded.
- Add `quote_version_packages` for at most three ordered package snapshots.
- Extend `quote_version_lines` with a line kind, required/optional/package membership, and stable ordering. A priced
  line belongs to exactly one choice mode; text/headings carry no quantity or money.
- Store Discount/Tax names, kinds, basis points/minor-unit values, customer visibility flags, customer copy, totals,
  calculation result, document hash, and frozen time on the version.
- Reference existing attachment objects through a tenant-scoped version attachment table with customer visibility;
  published references reject update/delete. Existing internal Attachments behavior remains private by default.
- One database function calculates selected subtotal, proportional Discount allocation, per-line exclusive Tax,
  cost, profit, margin, and Total. TypeScript formats returned money and never recreates persisted arithmetic.
- Freeze locks Quote then draft version, recalculates, validates, hashes canonical customer-visible content, assigns
  the next version number, and makes the snapshot immutable. Clone copies the last published snapshot into the one
  allowed mutable draft and bumps Quote ownership pointers atomically.
- Every child duplicates `organization_id`, uses tenant-safe composite foreign keys, enables RLS, and receives an
  index for its parent read and every RLS predicate. Function execution is revoked from PUBLIC/anon and granted by
  exact signature only.
- Quote detail and version reads are bounded single-record reads; package/line/section children are fetched in
  shaped batches. No new list needs pagination or a materialized view in Part 4.

## Slices

| Slice | Scope | Completion gate |
| --- | --- | --- |
| 4A | Migration: proposal/version shape, package and visible-attachment children, exact calculator, freeze/clone commands, immutability guards, RLS, grants, indexes | pgTAP covers tenant crossing, permissions, arithmetic fixtures, package limits, immutable children, revision conflicts, freeze/clone, and index-backed reads; database performance review passes |
| 4B | Draft command/API layer: Discount, Tax, choices, visibility, customer copy, and attachment visibility; extend permission-shaped Quote reads | Every POST/PATCH uses Zod, expected revision, `P0409`, no-store writes, precise payloads, and focused invalidation; route tests and API performance review pass |
| 4C | Shared Products & Services choice editor: required/optional/package modes, package management, text/headings, tax exemption, and database-returned totals | Composer and detail preserve shared Request behavior, keyboard/accessibility checks pass, Svelte validation and component performance review pass |
| 4D | Financial rail and proposal sections: Summary, Discount and Tax dialogs, Introduction, Client message, Contract disclaimer, client visibility, and customer-visible attachments/images | Desktop and mobile browser checks cover add/edit/remove, exact totals, staged media visibility, honest permissions, and no Deposit/template controls; Svelte and performance gates pass |
| 4E | Version foundation integration and carried browser gate: staff version read/history affordance only where truthful, freeze/clone integration tests, full Part 3D verification | Published snapshots and children cannot change, clone preserves history, Part 3 Quote #1/#31 checks pass, production build/unit/database/security/performance gates pass |

## Checklist

- [x] 4A database foundation and database performance gate - applied and verified 2026-08-20
- [x] 4B API commands/reads and API performance gate - applied and verified 2026-08-21
- [x] 4C choice editor and shared Request regression gate - verified 2026-08-21
- [x] 4D financial rail, proposal sections, visibility/media, and first browser pass - 2026-08-21
- [x] 4E version read, immutable integration, browser gate, and closeout - 2026-08-21

## What 4D shipped and fixed

- Rail: `QuoteSummaryCard` now shows Subtotal, Discount and Tax only when non-zero, Total, and
  Cost/Estimated profit/Margin behind `quotes.view_cost`. `QuoteDiscountCard` and `QuoteTaxCard` carry their
  own dialogs and write immediately; every other new block stages for the page's save bar.
- Main column: Introduction, `QuoteClientViewBlock`, `QuoteClientFilesBlock`, Client message, then the
  existing Contract disclaimer.
- One save press chains commands, feeding each returned revision into the next, so a multi-block save cannot
  make its own second write stale.
- **Two real bugs found only in the browser.** `runQuoteCommand` had pulled `supabase.rpc` into a variable,
  which loses the client and threw inside supabase-js: every 4B command route answered 500 and the mocked
  route tests could not see it. And the Quotes list `Total` column was selecting the version's
  `subtotal_minor`, which stopped being the total the moment a discount or tax existed.
- Browser-verified on Quote #31: 10% discount (−$50.10), 5% tax on the discounted base ($22.55), Total
  $473.45, removal recalculating to $526.05, staged client-view and file changes saving together with the
  introduction, and the list total agreeing with the detail.

## What 4B left for 4C

- Migrations `20260821090000_quote_proposal_draft_commands`, `20260821100000_quote_calculation_single_pass`, and
  `20260821110000_quote_lines_name_their_quote` are applied and recorded in remote history.
- Commands: `set_quote_draft_discount`, `set_quote_draft_tax`, `set_quote_draft_visibility`,
  `set_quote_draft_copy`, `replace_quote_version_packages`, `replace_quote_version_attachments`, the
  choice-aware `replace_quote_version_lines`, and the read-only `preview_quote_version_totals`.
- Every command goes through `private.lock_quote_draft` (permission, draft, revision) and ends in
  `private.bump_quote_draft`, which recalculates totals and returns `{revision, totals}` with no cost keys.
- Routes: `PATCH /api/quotes/[id]/{discount,tax,visibility,copy,packages,attachments,lines}` and
  `POST /api/quotes/[id]/preview`, all through `runQuoteCommand` in `src/lib/server/quotes/commands.ts`.
- The quote read now returns packages, version attachments, proposal copy, visibility, and discount/tax;
  version totals follow `quotes.view_price` and cost/profit/margin/`calculation` follow `quotes.view_cost`.
- Packages must be saved before lines, because a package line names an id the package command returns.
- 67 new pgTAP tests, 20 new route tests, 759 unit tests, and `npm run check` pass.
- The calculator was rewritten as one windowed pass during the performance gate: 93 ms and 2214 buffers on a
  200-line draft became 5.5 ms and 25. 4A's arithmetic assertions still pass unchanged.

## Required behavior

- Required lines are always selected; add-ons are independent; package approval later selects exactly one package.
- A draft preview may show a staff-selected package/add-on scenario, but it cannot record a customer decision.
- Fixed Discount cannot exceed selected subtotal. Percentage Discount rounds once, reduces non-taxable value first,
  then taxable value, and allocates leftover minor units in stable line order.
- Tax applies per taxable line after Discount. One Quote cannot mix currencies.
- Summary shows Subtotal, Discount, Tax, Total and authorized internal Cost/profit/margin only.
- Empty Discount/Tax rail blocks show explicit Add actions; configured blocks show value and Edit. Dialogs own
  Cancel and verb-named Save/Remove actions.
- Customer visibility independently controls quantities, unit prices, line totals, and totals.
- Customer-visible files are version references, not public attachment rows. Private Notes and internal attachments
  never enter the customer snapshot.
- Published version numbers are assigned at freeze time; drafts do not consume numbers.

## Risks and edge cases

- Existing `version_number = 1` drafts predate the approved publish-only numbering rule; 4A must migrate them without
  losing Quote #1 or #31 and must prove the first frozen number is deterministic.
- Current line totals are generated from ordinary priced lines. Changing line kinds must preserve Request-to-Quote
  copies and keep text/headings out of money checks.
- Draft revision is shared across header and lines. Every new command must participate in the same revision contract
  so a rail dialog cannot silently overwrite a concurrent line save.
- A package deletion or reorder must not leave lines pointing at a missing package or change stable allocation order.
- Discount/Tax calculation must survive zero totals, fractional quantities, half-minor-unit boundaries, maximum
  values, taxable/non-taxable mixes, all add-on combinations, and each package selection.
- The live Jobber tour for unrecorded package/section/version interactions is pending because no browser was connected
  during planning. Record only observed behavior before using it to refine UI interaction.
- The Part 3D browser gate reactivates during 4D's first browser pass and must finish in 4E.

## Pointers

- `docs/quote-behavior-contract.md` - permanent financial, version, choice, permission, and command rules.
- `.claude/skills/jobber/jobber-03-quotes.md` §3.2 and §8 - competitor choices and observed Quote surfaces.
- `.claude/skills/jobber/jobber-08-screen-patterns.md` - detail editing and optional-section behavior.
- `Design/Quotes new.jpg` and `Design/Quote Details.jpg` - placement blueprints.
- `parts/03-staff-quote-workspace.md` - shipped draft/revision/UI seams and carried browser gate.
