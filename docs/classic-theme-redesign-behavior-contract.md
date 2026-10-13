# Classic theme redesign

**Status:** First version (six record pages, card shells everywhere, four additions) approved by Jafar on
2026-10-13. New Classic look chosen the same day (§ Direction agreed so far › New Classic look); designing
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

## Direction agreed so far

- **Name:** `classic-theme-redesign` (Jafar, 2026-10-13).
- **Classic itself changes.** This redesigns the live default. Botanical stays a separate theme owned by the
  [CRM design system](crm-design-system-behavior-contract.md) campaign.
- **New Classic look** (Jafar, 2026-10-13: "I like your design very much. This will be our classic design, we
  will build design system based on your version. No more old version."). The reference screens are
  `Settings · Home · Claude concept · 1440` and `Settings · Business profile · Claude concept · 1440` in
  `classic.pen`; the [design recipe](classic-theme-redesign-design-recipe.md) records their values. Jafar
  asked for a design review of them before the family is redrawn.
- **Earlier family superseded.** The job concept (`Job details · Claude concept · Job cockpit · 1440`, Jafar:
  "I really like the design"), the quote, invoice and first Settings screens drawn from it, and the old
  Classic design-system page keep their approved **page structure** — header card, lifecycle track, key
  facts, rail order, the four layout moves — but their look is replaced. The two Codex concepts
  (`Refined Classic`, `Premium Split Sidebar`) were never chosen.
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
- **The design system is rebuilt from the new look** (Jafar, 2026-10-13). The Classic design-system page in
  `classic.pen` is redrawn from the reference screens: every colour, corner, shadow and part becomes a named
  token or reusable part with light and dark values, before the record pages are redrawn. Code and the
  Classic design skill take the same values when built. Earlier rule kept: when a page needs a part to look
  different, the part changes on the design-system page and every screen follows ("if new design require to
  change any design system we will do it to match").
- **The app shell takes the new look with the first version.** The dark sidebar and the top bar appear on
  every page, so like the card shells they change everywhere at once.
- **Colour where it means something** (Jafar, 2026-10-13: "not too much colorful … like rainbow, rather
  follow the best ui/ux designer"; then "you can use rainbow like different color where it make sense").
  Colour marks a settings section, a record type or a status; everything else stays neutral. The recipe's
  § Colour rule lists the colours.
- **Pencil only for now** (Jafar, 2026-10-13): no app code changes until the family is approved and build
  planning (Part 3) is done.

## Design principles

Drawn from the job concept; later screens follow them unless Jafar changes them.

1. **Answer the record's questions first.** The header card shows where the record stands (the lifecycle
   track), who and where it is for, and its key facts. Attention items show where the work is — today's visit
   in the visit list, not in a separate warning box.
2. **Colour carries meaning only.** Section, record type or status — the recipe's § Colour rule. Green
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
- **Six ideas in the new look** — not in the app yet; each needs Jafar's yes before it is built: a "Search
  settings" box; a Setup status card (Stripe, texting, email readiness); the Communication Balance figure on
  Settings home; a "What customers see" preview on Business profile; a "Where this is used" card; the Save
  bar's "You have unsaved changes" text. Until then they are drawn but not approved.
- **Old screens in `classic.pen`** — whether the superseded frames are deleted or moved to an archive area.
- **Home and Reports screens** — drawn in `classic.pen` for the CRM launch readiness campaign (Part 13) with
  the old parts, waiting for Jafar's yes; they take the new look once the design-system page is rebuilt.
- **"Control room" above Settings** (design review, 2026-10-13) — the Settings page's small heading says
  "Control room", the same name as the Uplift Control Room. Recommended: "Workspace".
- **Business group split** (design review) — the Business group holds 13 settings but its description fits
  only identity, look and hours. Recommended: Business (Business profile, Branding, Business hours, Taxes,
  Payments) and "Sales & work" in customer-journey order (Request Forms, Contact matching, Pipeline, Price
  Book, Quote Settings, Checklists, Invoice Settings, Google reviews).
- **Category pills** (design review) — the concept draws an "All settings" pill lit like a filter; the app's
  pills jump to a group. Recommended: keep jumping, drop "All settings", light the group being viewed, and
  keep counts only on the group headers.
- **Whole-app boundary** — whether later stages also cover login and the pages customers see (request forms,
  client portal, quote approval, payment pages). Does not block the first version.

## Not doing

- Changing Botanical — the CRM design system campaign owns it.
- Pages beyond the six record pages in the first version — they come in later stages.
- Adding, removing or re-permissioning features, beyond the approved additions.

## Sources and design decisions

- [Design recipe](classic-theme-redesign-design-recipe.md) — read before designing or building any screen for
  this campaign: the working method and exact sizes, spacing and styles of the reference screens.
- `classic.pen` screens `Settings · Home · Claude concept · 1440` and `Settings · Business profile · Claude
  concept · 1440` — the new Classic look.
- [Jobber screen patterns](../.claude/skills/jobber/jobber-08-screen-patterns.md) — detail-page skeleton,
  one primary action named for the next step, history and More placement.
- [CRM design system plan](crm-design-system-behavior-contract.md) — theme separation and Classic's role.
