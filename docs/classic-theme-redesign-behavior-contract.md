# Classic theme redesign

## Summary

This campaign redesigns and rebuilds **the whole desktop web application**, in stages, with new concepts that feel premium, polished,
modern, colorful, clear, calm and useful. The first delivery covers shared parts and six record pages; the
remaining Business Workspace, Uplift Control Room, sign-in and customer-facing journeys follow. 


## First version

Finish the Classic shared parts, then the six record pages that share them: job, quote, invoice, request,
payment and client. Their approved desktop Pencil designs are the starting points. Each works in light and
dark appearance on desktop. Other Classic pages already
receive the shared card style; their full layouts are redesigned in later stages.


## Design target

- **Top-tier UI/UX:** Jafar likes the visual craft he sees on Dribbble and wants that level of quality in
  the application (clarified 2026-10-15). Use that inspiration for composition, spacing, color, detail and
  polish while making real contractor tasks easy to understand and complete.
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
2. For each screen, research the user's task and the current behavior, create a new desktop Pencil concept,
   and get Jafar's approval. Earlier approved desktop screens retain their approval.
3. Build that screen using the shared parts. Check the main journey in the live desktop app, light
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

### Unified inbox additions

Jafar approved these with the `Communications · Inbox · 1440` concept on 2026-10-15. Each follows the
[unified inbox contract](unified-inbox-behavior-contract.md) for permissions and channel rules:

- **List:** a filter button beside search; short times (10:11 AM, Yesterday, Oct 13); "You:" or "Auto:" before
  a preview when the business sent the last message; a channel badge on each avatar.
- **Conversation header:** the assignee picker and Follow move here from the customer panel, joined by Mark as
  unread (opening still marks read, as Jobber allows), Archive and a More menu.
- **Timeline as a chat:** customer bubbles left, team bubbles right; time and delivery ticks under each bubble;
  an email reply shows a quote of the message it answers; Details, Forward and More appear on hover; a "New"
  divider marks messages since the last visit.
- **Internal notes:** a Reply / Internal note switch in the composer and violet note bubbles with @mentions,
  visible only to the team.
- **Customer panel:** Call / Text / Email buttons under the name (Text and Email switch the composer channel), a
  dark "Open job" card with next visit, crew, approved quote and Open job, and an Address row in Contact.


## References

- [Design recipe](classic-theme-redesign-design-recipe.md) — read before designing or building any screen for
  this campaign: the working method and exact sizes, spacing and styles of the reference screens.
- `classic.pen` screens `Settings · Home · Claude concept · 1440` and `Settings · Business profile · Claude
  concept · 1440` — the new Classic look.
- [Jobber screen patterns](../.claude/skills/jobber/jobber-08-screen-patterns.md) — detail-page skeleton,
  one primary action named for the next step, history and More placement.
- [CRM design system plan](crm-design-system-behavior-contract.md) — theme separation and Classic's role.
