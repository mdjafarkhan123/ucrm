# Classic theme redesign

## Summary

Classic is the design every contractor business uses today and the default for new businesses. This campaign
redesigns and rebuilds **the whole application**, in stages, with new concepts that feel premium, polished,
modern, colorful, clear, calm and useful. The first delivery covers shared parts and six record pages; the
remaining Business Workspace, Uplift Control Room, sign-in and customer-facing journeys follow. The theme
selection foundation still covers only the signed-in Business Workspace in its first release; this campaign
does not silently extend that separate contract. Existing features, permissions and save rules remain unless
Jafar separately approves a behavior change.

## Problem and audience

Owners, office staff and crews of contractor businesses using Classic; their customers on application-owned
pages; and later Jafar and his team in the Control Room.
Today's record pages give every section the same weight: empty sections take as much room as busy ones, and
the answers people open a record for — where it stands, whether anything needs attention today, and whether
it makes money — have to be hunted for across a long stack of similar boxes.

## First version

Finish the Classic shared parts, then the six record pages that share them: job, quote, invoice, request,
payment and client. Their approved desktop Pencil designs are the starting points; phone
adaptations are reviewed before each page is coded. Each works in light and dark appearance. Other Classic pages already
receive the shared card style; their full layouts are redesigned in later stages.

## Later stages

The whole application follows gradually: the five approved lists; Schedule; Settings; Home and Reports;
remaining Business Workspace areas and forms; the Uplift Control Room; and sign-in, setup and customer-facing
journeys. Inventory routes and shared parts before each later stage so no screen is silently skipped. The
currently approved sequence and later-stage gates live in the [roadmap](../Memory/campaigns/classic-theme-redesign/ROADMAP.md).

## Design target

- **New concepts come first.** Do not copy the live screen into Pencil and call it a redesign, and do not add
  decoration without a purpose. Study the actual task and mature products relevant to it, then design a fresh
  layout that makes the important answer or action easy to find. If an existing idea genuinely works best,
  keep it and explain why. Jafar approves what people see before it is built.
- **Visual quality:** Aim for the care of a leading product designer's work: premium, polished, modern,
  colorful, clear, calm and meaningful. Icons and accents may use multiple colors wherever that improves
  beauty and clarity. Keep status meanings consistent and ensure color never becomes the only way to
  understand information.

## Design and build loop

1. Establish the design-system foundations and **all shared parts needed by the approved screen batch** in
   `classic.pen`, including states. Show Jafar the new or materially changed parts, record approval, then build
   and verify their Classic-only implementation. Extend the system when later screens reveal a real need;
   do not spend months inventing parts for hypothetical screens.
2. For each screen, research the user's task and the current behavior, create a new Pencil concept at desktop
   and phone widths, and get Jafar's approval. Earlier approved desktop screens retain their approval; add
   and review their phone adaptation before coding without reopening the settled desktop concept.
3. Build that screen using the shared parts. Check the main journey in the live app, desktop and phone, light
   and dark, relevant roles, and the states it touches. Keep Botanical unchanged.
4. If the screen improves a shared part, update its Pencil master, code component and design guidance in the
   same delivery. Remove the finished screen's superseded app styling and rejected Pencil variants after the
   approved reference is safely saved. Then move to the next screen. Limit new speculative Pencil work while
   implementation is behind.

## Design principles

These describe the approved record-page concepts. Later screen concepts use the parts that fit their task;
they do not have to copy a record-page layout.

1. **Answer the record's questions first.** The header card shows where the record stands (the lifecycle
   track), who and where it is for, and its key facts. Attention items show where the work is — today's visit
   in the visit list, not in a separate warning box.
2. **Color adds meaning and visual quality.** Multicolor icons and accents are allowed where they make the
   design more beautiful or easier to scan. Status colors stay consistent: green means done or happening now,
   amber waiting, red needs action. See the recipe's color guidance.
3. **Small things stay small.** An empty section shows its prompt and action compactly. Related small sections
   can share one card with tabs, as the job's Work log does for time, expenses and checklists.
4. **Work on the left, money and wrap-up on the right.** The main column holds the work (visits, line items,
   work log). The right column holds profit, close-out, billing, instructions, photos and notes.
5. **One calm surface style.** White cards with 20px corners, a hairline border and a soft shadow on a cool
   light-grey page, a dark sidebar, at most one dark featured card per page, and one ink primary button per
   page, named for the next step.

## Shared building blocks

Restyling one changes every page listed.

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

These additions are part of the agreed scope:

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
- Every existing action on redesigned pages still works for the same roles, with the same save behavior.
- Classic dark appearance and phone width show every redesigned page without cut-off or overlapping parts.
- Botanical pages look the same before and after this campaign's changes.
- The route inventory shows every application area assigned to a stage; each completed screen has an approved
  design, a checked live journey and no obsolete local variant left as the current design.

## Technical boundaries

- The pages above share the listed blocks.
- Page content styles are not yet fully separated by theme; the Classic frame marks
  `data-presentation="classic"`. Restyling a shared block would also change Botanical, so build planning must
  use the CRM design system's theme foundation for Classic-only styling.

## Still unclear

- The exact order and screen boundaries within later Business Workspace, Control Room, sign-in and
  customer-facing stages are chosen from the route inventory before those stages begin.

## Not doing

- Changing Botanical — the CRM design system campaign owns it.
- Adding, removing or re-permissioning features, beyond the approved additions.

## References

- [Design recipe](classic-theme-redesign-design-recipe.md) — read before designing or building any screen for
  this campaign: the working method and exact sizes, spacing and styles of the reference screens.
- `classic.pen` screens `Settings · Home · Claude concept · 1440` and `Settings · Business profile · Claude
  concept · 1440` — the new Classic look.
- [Jobber screen patterns](../.claude/skills/jobber/jobber-08-screen-patterns.md) — detail-page skeleton,
  one primary action named for the next step, history and More placement.
- [CRM design system plan](crm-design-system-behavior-contract.md) — theme separation and Classic's role.
