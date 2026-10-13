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
- **Keep the approved Settings sidebar** (Jafar, 2026-10-13). Later split-rail, navigation-tile and editorial
  sidebar alternatives were rejected and deleted; the sidebar shown on the two approved Settings reference
  screens remains the Classic direction.
- **Colour where it means something** (Jafar, 2026-10-13: "not too much colorful … like rainbow, rather
  follow the best ui/ux designer"; then "you can use rainbow like different color where it make sense").
  Colour marks a settings section, a record type or a status; everything else stays neutral. The recipe's
  § Colour rule lists the colours.
- **Brand colour is green** (Jafar, 2026-10-13: "preserve my brand color which is Green. You can use its
  shade if you want where need like Very deep green, deep green etc."). Every green in the new look comes from
  the app's green scale (`--color-base-green--100` to `--1000`), replacing the concept's other greens.
- **Green buttons, black-green sidebar** (Jafar, 2026-10-13: "Main button is green, my brand color, sidebar
  we can use black green type"; then "dont use light green in white mode … see our app which green we are
  using as brand"). The brand green is the one the app's buttons already use, `#037741`
  (`--color-interactive`, hover `#02532D`), with white text. It colours the main button, Save, the logo tile,
  the highlighted menu item and badges, replacing the concept's lime. Light mode uses no light green;
  `#05BE68` and lighter stay for dark mode, as in the app today. The sidebar and the other dark surfaces
  (Save bar, selected pill) are a near-black green instead of navy ink. One green button per page; other card
  actions are secondary.
- **Design review answers** (Jafar, 2026-10-13: "go with your recommendation"):
  - The review's fixes are applied: readable text contrast, "1 to do" on Setup status, a one-tile group spans
    the full width, side-by-side cards share a height, the app's own wording, and the always-visible Save
    bar's resting state on full-page forms.
  - Settings' small heading says "Workspace" instead of "Control room".
  - The Business group splits in two: Business (Business profile, Branding, Business hours, Taxes, Payments)
    and Sales & work in customer-journey order (Request Forms, Contact matching, Pipeline, Price Book, Quote
    Settings, Checklists, Invoice Settings, Google reviews).
  - Category pills keep jumping to a group: no "All settings" pill, the group in view is lit, and counts
    show only on group headers.
  - Superseded screens move to an Archive area of `classic.pen` and are deleted once Part 2B redraws the job,
    quote and invoice pages.
  - The Home and Reports screens for the launch campaign take the new look before Jafar approves them.
- **Design-system page approved** (Jafar, 2026-10-13: "ok including earlier … i approve your
  recommendation"). `Classic design system · light` and `· dark` in `classic.pen` hold the named light and
  dark tokens and the shared parts; both Settings reference screens are built from those parts. Its dark
  values, collapsed icons-only sidebar, field focus and error states, and the resting Save bar ("No unsaved
  changes" / "Change any field, then press Save.") are part of the approval.
- **"Soon" menu items are hidden** (Jafar, 2026-10-13). Growth Feed, Team, Notifications and Usage leave the
  sidebar until they are built, instead of showing greyed with "Soon".
- **Job details approved** (Jafar, 2026-10-13: "yes"). `Job details · 1440` in `classic.pen` keeps the first
  concept's section placement in the new look; its lifecycle track shows each record's icon tile in its
  record colour and its number ("Request #88", "Quote #318", "Job #1042"), linked records with an open arrow.
  A rearranged version (page header on the background, "Right now" card, merged rail cards) was drawn and
  rejected — keep the approved placement.
- **Icon colour must be meaningful** (Jafar, 2026-10-13, approved on the six record pages). A coloured icon tile
  tells the user something — a status needing attention, another record's type, or automation; everything else
  stays neutral. Details in the recipe § Colour rule.
- **Quote details approved** (Jafar, 2026-10-13: "yes"). `Quote details · 1440` in `classic.pen` is built
  from the approved Job and keeps the quote concept's placement. A sent quote shows no edit pencils (editing
  needs a draft; the products footer says to start a new version). The app's separate Discount and Tax rail
  cards appear as one "Discount and tax" card (approved with the screen as shown).
- **Invoice details approved** (Jafar, 2026-10-13: "yes"). `Invoice details · 1440` in `classic.pen` keeps the
  invoice concept's placement: Terms & dates as the hero's facts row with a pencil, Financial and Invoice
  history as History tabs, no Notes card (the app's invoice page has none).
- **Top-of-rail green card stays one design, Jobber-style** (Jafar, 2026-10-13). The deep green summary card
  keeps its single figure + breakdown (Jobber's job profitability box); no Settings choice of layouts. Its
  small text is brighter for readability: `feature-eyebrow #C2D6C9`, `-meta` and `-label #D5E3DA`,
  `-muted #B4C9BC` (≥5.3:1 on the whole gradient), text under 13px one size up. Later idea, only if
  contractors ask: a "Next step" card or an "At a glance" four-number card, or letting the owner choose which
  numbers show (HubSpot-style).
- **Request, Payment and Client details approved** (Jafar, 2026-10-13: "I approved your design").
  `Request details · 1440`, `Payment details · 1440` and `Client details · 1440` in `classic.pen` complete the
  six record pages. The request's Automatic follow-up card takes the green top-of-rail style. The payment page
  gains a right rail with a Receipt preview (View receipt, Print or save PDF), shows "Applied to" above
  "Details", and has no green card because its one figure is already the title. The client's Lifetime, Open
  quotes and Active jobs move from the header into the green card; Lead source and Marketing email share one
  "Source and marketing" card; Call, Message and Request review sit beside the name; the Details /
  Communication tabs sit at the foot of the header card. A new Segmented control part (Upcoming / Past) joins
  the design-system page. The superseded first-concept frames are deleted.
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
  this campaign: the working method and exact sizes, spacing and styles of the reference screens.
- `classic.pen` screens `Settings · Home · Claude concept · 1440` and `Settings · Business profile · Claude
  concept · 1440` — the new Classic look.
- [Jobber screen patterns](../.claude/skills/jobber/jobber-08-screen-patterns.md) — detail-page skeleton,
  one primary action named for the next step, history and More placement.
- [CRM design system plan](crm-design-system-behavior-contract.md) — theme separation and Classic's role.
