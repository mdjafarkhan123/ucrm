# Classic theme redesign

**Status:** First version (six record pages, card shells everywhere, four additions) approved by Jafar on
2026-10-13; all six record pages designed and approved, and the build order approved the same day. Building
next.

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

## Direction agreed so far (don not write a long history, before writing show jafar for approval)

- **Name:** `classic-theme-redesign` (Jafar, 2026-10-13).
- **Target:** Dont convert exsiting real app screen design to classic pencil design. Its not a conversion work neither a random design. A new design concept like how top ui/ux engnieer design theri product on Dribbble. Jafar Like their design. Premium, Polished, Modern, Colored, Clarity, Clam, Meaningful. New design should meet what contractors really want to see - no vauge. Design should be based on real world related top product research to know what really works and what not, which layout or element to add not to add, their positioning etc

## Design principles

Drawn from the job concept; later screens follow them unless Jafar changes them.

1. **Answer the record's questions first.** The header card shows where the record stands (the lifecycle
   track), who and where it is for, and its key facts. Attention items show where the work is — today's visit
   in the visit list, not in a separate warning box.
2. **Colour carries meaning only.** Different type of color (multicolor) is allowed where suits. Section, record type or status — the recipe's § Colour rule. Green
   means done or happening now, amber waiting, red needs action.
3. **Small things stay small.** An empty section shows its prompt and action compactly. Related small sections
   can share one card with tabs, as the job's Work log does for time, expenses and checklists.
4. **Work on the left, money and wrap-up on the right.** The main column holds the work (visits, line items,
   work log). The right column holds profit, close-out, billing, instructions, photos and notes.
5. **One calm surface style.** White cards with 20px corners, a hairline border and a soft shadow on a cool
   light-grey page, a dark sidebar, at most one dark featured card per page, and one ink primary button per
   page, named for the next step.

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


### Settings additions

Jafar approved these on 2026-10-13 ("go with your recommendation"):

- **Settings in the main search** — the top search finds settings pages too, instead of a second "Search
  settings" box on the page (as Stripe and Linear do).
- **Setup status card** on Settings home: Stripe, texting and email readiness, each with its next action.
- **Communication Balance figure** on Settings home.
- **"What customers see" preview** on Business profile.
- **"Where this is used" card** on settings pages.
- **Save bar wording**: "You have unsaved changes" once something changes; a resting state while nothing has.

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

- **Whole-app boundary** — whether later stages also cover login and the pages customers see (request forms,
  client portal, quote approval, payment pages). Does not block the first version.

## Not doing

- Changing Botanical — the CRM design system campaign owns it.
- Adding, removing or re-permissioning features, beyond the approved additions.

## Sources and design decisions

- [Design recipe](classic-theme-redesign-design-recipe.md) — read before designing or building any screen for
  this campaign: the working method and exact sizes, spacing and styles of the reference screens.
- `classic.pen` screens `Settings · Home · Claude concept · 1440` and `Settings · Business profile · Claude
  concept · 1440` — the new Classic look.
- [Jobber screen patterns](../.claude/skills/jobber/jobber-08-screen-patterns.md) — detail-page skeleton,
  one primary action named for the next step, history and More placement.
- [CRM design system plan](crm-design-system-behavior-contract.md) — theme separation and Classic's role.
