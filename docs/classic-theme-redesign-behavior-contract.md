# Classic theme redesign

**Status:** First version (six record pages, card shells everywhere, four additions) approved by Jafar on
2026-10-13; designing next.

## Summary

Classic is the design every contractor business uses today and the default for new businesses. This campaign
gives Classic a premium, polished, modern look — the standard of a top product designer's portfolio — while
keeping every existing feature, permission and save rule. It starts from the job details concept Jafar liked,
carries the same look to the other record pages that share its building blocks, and then continues gradually
through the whole app, including the Uplift Control Room (the `/jafar` panel).

## Problem and audience

Owners, office staff and crews of contractor businesses using Classic, and later Jafar in the Control Room.
Today's record pages give every section the same weight: empty sections take as much room as busy ones, and
the answers people open a record for — where it stands, whether anything needs attention today, and whether
it makes money — have to be hunted for across a long stack of similar boxes.

## First version

The six record pages that share building blocks: job, quote, invoice, request, payment and client (Jafar,
2026-10-13). Each is designed at desktop width in Pencil, then built with its phone layout adapted during the
build, and works in light and dark appearance. Every other Classic page takes the new card style at the same
time, without layout changes.

## Later stages

The rest of the app follows gradually, including the Uplift Control Room (Jafar, 2026-10-13). Their order and
grouping are planned after the first version, one stage at a time.

## Direction agreed so far

- **Name:** `classic-theme-redesign` (Jafar, 2026-10-13).
- **Classic itself changes.** This redesigns the live default. Botanical stays a separate theme owned by the
  [CRM design system](crm-design-system-behavior-contract.md) campaign.
- **Job details direction.** The Pencil screen `Job details · Claude concept · Job cockpit · 1440` in
  `classic.pen` (commit `52a16c7f`). Jafar, 2026-10-13: "I really like the design." Formal approval waits until
  the quote and invoice pages are designed with the same parts. The two Codex concepts in the same file
  (`Refined Classic`, `Premium Split Sidebar`) are earlier alternatives, not chosen.
- **Font stays Inter** (Jafar, 2026-10-13). The job concept used Plus Jakarta Sans; it is switched back to
  Inter before the family is designed.
- **Desktop designs only in Pencil** (Jafar, 2026-10-13). Phone layouts are adapted while building and must
  still pass the design skill's 390px screen check on the built page. This replaces, for this campaign only,
  the design skill's rule that each Pencil screen also exists at 390px.
- **No duplicated UI.** The redesign restyles the shared building blocks rather than making job-only copies.
  The line items block also appears in the request, quote, job and invoice create/edit forms, so those forms
  take its new look in the first version.
- **Card shells change everywhere at once** (Jafar, 2026-10-13). `SectionBlock` and `RailCard` take the new
  card look on every Classic page in the first version, so two card styles never live side by side; each
  page's layout still waits for its own stage. A Settings page with the new cards is shown in Pencil before
  building.
- **New colours become named tokens.** The concept's warm page background, hairline card border, today-row
  tint, profit-card colours, 20px corner and soft shadow are added to the Classic design-system page in
  `classic.pen` with light and dark values before the family is designed, then kept equal in code and the
  Classic design skill.

## Design principles

Drawn from the job concept; later screens follow them unless Jafar changes them.

1. **Answer the record's questions first.** The header card shows where the record stands (the lifecycle
   track), who and where it is for, and its key facts. Attention items show where the work is — today's visit
   in the visit list, not in a separate warning box.
2. **Colour carries meaning only.** Green means done or happening now, grey means waiting, and late, warning
   and record types use their existing status colours. Sections get no decorative coloured headers.
3. **Small things stay small.** An empty section shows its prompt and action compactly. Related small sections
   can share one card with tabs, as the job's Work log does for time, expenses and checklists.
4. **Work on the left, money and wrap-up on the right.** The main column holds the work (visits, line items,
   work log). The right column holds profit, close-out, billing, instructions, photos and notes.
5. **One calm surface style.** White cards with 20px corners, a hairline border and a soft shadow on a warm
   light-grey page; one green primary button per page, named for the next step.

## Shared building blocks

Checked in code 2026-10-13. Restyling one changes every page listed.

| Block | Pages using it |
| --- | --- |
| `layout/RecordDetailLayout` (page frame, right column, save bar) | Client, request, quote, job, invoice, payment, team member |
| `work/WorkRecordHeader` + `ClientSummaryCard` + `RecordFactsList` (header card) | Request, quote, job, invoice, payment |
| `quotes/ProductsAndServicesBlock` (line items) | Request, quote, job, invoice, and their create/edit forms |
| `NotesPanel` (notes) | Client, request, quote, job |
| `RecordFilesCard` (photos and files) | Client, request, quote, job, invoice |
| `QuoteSummaryCard`, `RecordDiscountCard`, `RecordTaxCard` (totals) | Quote, job, invoice |
| `SectionBlock`, `RailCard` (card shells) | Nearly every page, including Settings |

## Behavior that must not change

Look and layout change; behavior does not, beyond the approved additions below. Saving follows the shared
design workflow: nothing writes until the user presses a save button, and detail pages keep their one pinned
save bar. Permissions, loading and caching, preloading, and photo display rules stay as they are.

## Approved additions

Jafar approved all four on 2026-10-13, provided existing data supports each. Data checked the same day.

- **Lifecycle track** on work records — request, quote, job, invoice and payment pages, not the client page:
  Request → Quote → Job → Invoice → Paid, each page lighting its own step. Supported: a job records its source request or quote, invoice lines record their source job, and
  payments belong to invoices.
- **Close-out list** on jobs: what is left before invoicing. Supported: visits, checklists, photos, customer
  signatures and the work report all exist on the job page today.
- **Quick contact buttons** in the header: call, text and directions. Call already exists as a phone link on
  the client card; directions can open a map link for the property address. What **Text** opens is still
  unclear.
- **Live on-site time** on today's visit. Supported: running timers record their job and visit.

## Success checks

- An owner opens an in-progress job → without scrolling sees its stage, today's visit, the job total and what
  is left before invoicing.
- Every existing action on the redesigned pages still works for the same roles, with the same save behavior.
- Classic dark appearance and phone width show every redesigned page without cut-off or overlapping parts.
- Botanical pages look the same before and after this campaign's changes.

## Assumptions

- Confirmed: the pages above share the listed blocks (code check 2026-10-13).
- Confirmed: page content styles are not yet separated by theme; the Classic frame only marks
  `data-presentation="classic"`. Restyling a shared block would also change Botanical, so build planning must
  use the CRM design system's theme foundation for Classic-only styling. This is technical and coordinated
  with that campaign, not a choice for Jafar.

## Still unclear

- **Text button** — whether it opens the client's conversation in the app's inbox or the device's messaging
  app, given business texting is not yet active. Does not block design; settle before building the header.
- **Whole-app boundary** — whether later stages also cover login and the pages customers see (request forms,
  client portal, quote approval, payment pages). Does not block the first version.

## Not doing

- Changing Botanical — the CRM design system campaign owns it.
- Pages beyond the six record pages in the first version — they come in later stages.
- Adding, removing or re-permissioning features, beyond the approved additions.

## Sources and design decisions

- [Design recipe](classic-theme-redesign-design-recipe.md) — read before designing or building any screen for
  this campaign: the working method and exact sizes, spacing and styles of the reference screen.
- `classic.pen` screen `Job details · Claude concept · Job cockpit · 1440` — the direction Jafar liked.
- [Jobber screen patterns](../.claude/skills/jobber/jobber-08-screen-patterns.md) — detail-page skeleton,
  one primary action named for the next step, history and More placement.
- [CRM design system plan](crm-design-system-behavior-contract.md) — theme separation and Classic's role.
