# Classic theme redesign

**Status:** Planning — campaign created 2026-10-13; first-version scope not yet approved.

## Summary

Classic is the design every contractor business uses today and the default for new businesses. This campaign
gives Classic a premium, polished, modern look — the standard of a top product designer's portfolio — while
keeping every existing feature, permission and save rule. It starts from the job details concept Jafar liked
and carries the same look to the other record pages that share its building blocks, so the app stays
consistent instead of half old, half new.

## Problem and audience

Owners, office staff and crews of contractor businesses using Classic. Today's record pages give every
section the same weight: empty sections take as much room as busy ones, and the answers people open a record
for — where it stands, whether anything needs attention today, and whether it makes money — have to be
hunted for across a long stack of similar boxes.

## First version

Proposed, not yet approved: the six record pages that share building blocks — job, quote, invoice, request,
payment and client — at desktop and phone width, in light and dark appearance. The exact scope waits on the
questions in **Still unclear**.

## Direction agreed so far

- **Name:** `classic-theme-redesign` (Jafar, 2026-10-13).
- **Classic itself changes.** This redesigns the live default. Botanical stays a separate theme owned by the
  [CRM design system](crm-design-system-behavior-contract.md) campaign.
- **Job details direction.** The Pencil screen `Job details · Claude concept · Job cockpit · 1440` in
  `classic.pen` (commit `52a16c7f`). Jafar, 2026-10-13: "I really like the design." It is desktop only so far;
  formal approval waits until the quote and invoice pages are designed with the same parts. The two Codex
  concepts in the same file (`Refined Classic`, `Premium Split Sidebar`) are earlier alternatives, not chosen.
- **No duplicated UI.** The redesign restyles the shared building blocks rather than making job-only copies.

## Design principles

Drawn from the job concept; later screens follow them unless Jafar changes them.

1. **Answer the record's questions first.** The header card shows where the record stands (a lifecycle
   track), who and where it is for, and its key facts. Attention items show where the work is — today's
   visit in the visit list, not in a separate warning box.
2. **Colour carries meaning only.** Green means done or happening now, grey means waiting, and late, warning
   and record types use their existing status colours. Sections get no decorative coloured headers.
3. **Small things stay small.** An empty section shows its prompt and action compactly. Related small
   sections can share one card with tabs, as the job's Work log does for time, expenses and checklists.
4. **Work on the left, money and wrap-up on the right.** The main column holds the work (visits, line items,
   work log). The right column holds profit, close-out, billing, instructions, photos and notes.
5. **One calm surface style.** White cards with 20px corners, a hairline border and a soft shadow on a warm
   light-grey page; one green primary button per page, named for the next step.
6. **Font:** Plus Jakarta Sans in the concept — proposed, see **Still unclear**.

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

Look and layout change; behavior does not, unless Jafar approves a proposal below. Saving follows the shared
design workflow: nothing writes until the user presses a save button, and detail pages keep their one pinned
save bar. Permissions, loading and caching, preloading, and photo display rules stay as they are.

## Proposed new behavior

Shown in the job concept; each needs Jafar's yes and a check that existing data supports it.

- **Lifecycle track** on work records: Request → Quote → Job → Invoice → Paid, each page lighting its own step.
- **Close-out list** on jobs: what is left before invoicing, gathered from existing photos, checklists, visits,
  customer signature and work report.
- **Quick contact buttons** in the header: call, text and directions.
- **Live on-site time** on today's visit, from time-clock entries.

## Success checks

Draft; finalized with the approved scope.

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
- Unverified: whether each proposed behavior can be built from existing data.

## Still unclear

- **Scope** — which pages the first version covers. Blocks the first version.
- **Font** — switch all of Classic to Plus Jakarta Sans, or keep Inter. Blocks design.
- **Phone designs** — design each page's phone version in Pencil before building, or adapt during the build.
  Blocks design.
- **Proposed new behavior** — which of the four belong in the first version.

## Not doing

- Changing Botanical — the CRM design system campaign owns it.
- Control Room, login and customer-facing pages — they keep their current look in the first release.
- Adding, removing or re-permissioning features, beyond approved proposals.

## Sources and design decisions

- `classic.pen` screen `Job details · Claude concept · Job cockpit · 1440` — the direction Jafar liked.
- [Jobber screen patterns](../.claude/skills/jobber/jobber-08-screen-patterns.md) — detail-page skeleton,
  one primary action named for the next step, history and More placement.
- [CRM design system plan](crm-design-system-behavior-contract.md) — theme separation and Classic's role.
