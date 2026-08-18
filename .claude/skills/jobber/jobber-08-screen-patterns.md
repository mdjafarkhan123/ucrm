# Jobber Screen Patterns — Detail Pages, Editing, Lists

**Source:** live walkthrough of Jafar's own Jobber account on 2026-08-17 — client, request, quote, job, and
invoice detail pages, plus the quote, job, and invoice lists. Observed in the product, not from the help
centre. Where a rule below was seen on some pages and not others, that is said explicitly.

This file covers **how a screen behaves**. It does not cover how it looks: colour, type, spacing, and
component choice come from `.claude/skills/design/`, and where a block sits on the page comes from the
blueprint in `Design/`.

---

## The shared detail-page skeleton

Every work record — request, quote, job, invoice — is built the same way:

- A coloured bar across the top of the card, tinted by status.
- A status pill and a record-type icon on the left of the header row.
- On the right of the same row: a history icon, a `More` menu, and exactly **one green primary action**,
  named for the next step in the lifecycle (`Email Booking Confirmation`, `Convert to Job`,
  `Show Late Visit`, `Send Email`).
- The record title as the page heading, with an edit pencil at the far right. **Observed live 2026-08-18:**
  the pencil swaps the heading in place for a full-width text field labelled `Request title`, sitting exactly
  where the heading was — no block opens underneath it — and the pencil disappears while the field is open.
  Cancel and Save then appear at the bottom of the header card. Our `work/WorkRecordHeader.svelte` does the
  same swap for every work record; only the save pair differs, because this app puts it in the page's one
  pinned bar instead.
- Below the heading, two columns: a **client card** on the left (name, addresses, phone, email, and a `...`
  menu) and a **facts column** on the right — plain label/value rows of the few dates and numbers that
  identify the record.
- Then the body sections, each a card with its own pencil.
- A right rail. Notes appears on every page; the rest is per record (profit margin on a job, client-view
  toggles on an invoice, tags and last communication on a client).

The client detail page follows the same skeleton with tabs (`Client information`, `Communication`) instead
of body sections straight away.

**Tabs, observed live 2026-08-17.** The strip sits below the header card and above the body, and it governs
the body only — the right rail does not change with the tab. Underline tabs, the active one marked by a
green bar. **The open tab travels in the URL as `?tab=communication`**, so a tab survives a reload and can
be linked to; the default tab carries no parameter.

## The three edit patterns, and which one to use

Jobber does not have one edit interaction. It has three, and the choice depends on **what record owns the
fields**, not on which page you are standing on.

1. **A record's own fields edit in place, block by block.** Clicking a section's pencil turns that block
   into a form where it sits. Every other block stays read-only, and the page does not navigate. A **Cancel
   and Save pair appears at the bottom of that block** — it belongs to the block and scrolls with it; it is
   not pinned to the viewport. Seen on request title, request Overview, request and quote Product/Service,
   quote Contract/Disclaimer.
2. **A different record, edited from a page that only references it, opens a modal.** The client's own page
   edits the client in an `Edit Client` modal and each property in an `Edit A property` modal. Each modal
   holds that whole record's form and owns its own footer: Cancel and a verb-named save (`Update Client`,
   `Save`), with `Delete` bottom-left where deleting is allowed.
3. **The full edit page still exists, reached from elsewhere.** From a work record, the client card's `...`
   menu offers `View client profile` and `Edit client details`; the second opens `/clients/[id]/edit` in a
   new tab. That page puts section labels and helper text down the left, fields on the right, and a **sticky
   bar pinned to the bottom of the viewport: Delete on the left, Cancel and Update Client on the right.**

So a sticky save bar is a real Jobber pattern — it belongs to a full-page form, not to a detail page.

### Editing reveals controls that reading hides

A block in edit mode grows controls that are absent while reading: `Add Line Item`, `Add Text`,
`Mark as optional`, `Add Discount`, `Add Tax`, `Client view / Change`. Do not show those affordances on a
read-only block.

## Sections

- **An empty section shows its prompt and its action, not a pencil.** The job's Product/Service block reads
  "Keep everything on track by adding products and services" with an `Add Line Item` button and no pencil.
  A section only earns a pencil once it holds something to edit.
- **Optional sections are added, not shown empty.** Quotes and invoices put `+ Add section` chips between
  blocks — Introduction, Attachments, Images, Client Message. The section does not exist on the record until
  the contractor adds it.
- **A section can hold a table with its own furniture:** a filter chip, a `+` button, per-row action icons
  (complete, edit), and its own pagination ("Showing 1-10 of 14 items"). The job's Visits table does all
  four.
- **A section can hold tabs.** The job's Billing block has `Invoicing` and `Reminders` tabs plus an
  `Edit Invoice Settings` button in its header.

## Notes, on every record

- With no notes: one dashed box, a plus in the middle, and the line "Leave an internal note for yourself or
  a team member". Clicking anywhere in it swaps the box for the composer — there is never a composer and an
  empty banner on screen at once.
- The composer is a textarea ("Use @ in notes to mention your team"), an attach files and photos dropzone, a
  `Link to related` collapsible, and Cancel plus Save. Cancel returns to the empty box.
- With notes: the rail card header carries a `+` button, and each note shows author avatar, name, timestamp,
  a pin marker when pinned, and edit and `...` controls.

## List pages

Quotes, jobs, and invoices share one shape, top to bottom:

1. Page title, a green `New X` button, and a `More Actions` menu.
2. A row of stat cards. The first is always an **Overview** card of status counts with a coloured dot per
   status; the rest are trend cards for the last 30 days.
3. The result heading with a count: "All quotes (1 result)".
4. Filter chips (`Status | All`, `Date | All`, `Job Type | All`) on the left, a search box on the right.
5. The table: client first, then the record number stacked over its title, then property, dates, a status
   badge, and money right-aligned. Sortable columns carry a sort caret.

---

## Reusable parts inventory

**Observed live 2026-08-18** across the quote detail (`/quotes/63225286`), the invoice detail
(`/invoices/165953012`), the client detail (`/clients/147801604`), the quote and invoice lists, and the
`New Quote` and `New Invoice` forms. Read with the job and request notes in `jobber-02` and `jobber-04`.

Which screens actually use each part:

| Part                                      | Request | Quote | Job | Invoice | Client                                    |
| ----------------------------------------- | ------- | ----- | --- | ------- | ----------------------------------------- |
| Status-tinted top bar                     | yes     | yes   | yes | yes     | yes                                       |
| Record-type icon + status pill            | yes     | yes   | yes | yes     | yes                                       |
| History icon in header                    | yes     | yes   | yes | yes     | **no**                                    |
| `More` menu                               | yes     | yes   | yes | yes     | yes                                       |
| One green primary action                  | yes     | yes   | yes | yes     | **`+ Create` menu, not a lifecycle step** |
| Title heading + edit pencil               | yes     | yes   | yes | yes     | yes                                       |
| Client + property summary card with `...` | yes     | yes   | yes | yes     | **no — it is the client**                 |
| Facts column (label/value rows)           | yes     | yes   | yes | yes     | yes, but full width in two columns        |
| Body section cards with a pencil          | yes     | yes   | yes | yes     | yes                                       |
| `+ Add section` chips                     | no      | yes   | no  | yes     | no                                        |
| Line-item table with totals footer        | no      | yes   | yes | yes     | no                                        |
| Notes rail card                           | yes     | yes   | yes | yes     | yes                                       |
| Tabs below the header                     | no      | no    | no  | no      | yes                                       |

### What varies inside a shared part

- **Facts column length is per record, not a fixed pair.** Quote shows Quote # / Created / Approved.
  Invoice shows Invoice # / Issued / Payment terms. Build it as a list of label/value rows, not a
  two-slot component.
- **The facts column carries honest empties, not blanks.** The invoice's `Issued` reads "Not sent yet".
- **The client summary card has variable address slots.** The quote card shows only `Property Address`;
  the invoice card shows `Billing Address` and then `Property Address` with
  "No property associated with this item". Phone and email sit under the addresses in both.
- **The totals footer extends per record.** The quote stops at Subtotal / Total. The invoice adds a
  tinted band below it: `Invoice balance` and `Account balance (including this draft)`.
- **The right rail is ordered per record and Notes is not always first.** The invoice rail is
  `Client view` (a pencil plus five ON/OFF toggles: Quantities, Unit prices, Line item totals, Account
  balance, Late stamp) and then Notes. The quote rail is Notes only. The client rail is Overview
  (lifetime value, current balance), Tags with a `+`, Last communication with a chevron, then Notes.

### The create-page Primary Info card is one component

`New Quote` and `New Invoice` draw the identical card, and it matches `New Request`: status-tinted top
bar, record-type icon beside a `New X` heading, a full-width title field, a `Select a client` combobox on
the left, and a right column of record-specific fields ending in `Customize | Add Field`. Below it the
body blocks appear in their edit shape, and a sticky bar holds `Cancel` and a split green
`Save X` button.

Only the right column and the title label change per record — quote: `Quote #`; invoice: `Invoice #`,
`Issued date`, `Payment terms`, and the title field is labelled `Subject` and pre-filled
"For Services Rendered".

### Where the client list differs from the work-object lists

The work-object lists lead with an **Overview** status-count card; the client list has no such card, only
trend cards. Its filters are `Filter by tag +` and `Status`, and its heading reads
"Filtered clients (3 results)" rather than "All clients". The invoice list adds a `Balance` column and
puts money beside each status count inside the Overview card.

### The client's linked-work table

The client body carries a table of the client's own work records — one row per Request / Quote / Job /
Invoice, showing the record-type icon, type over title, property, created date, a status badge, and money
right-aligned. It is the list-page row shape reused inside a section.

---

## § How WE compare

- **We take all three of Jobber's edit patterns. Jafar, 2026-08-18. This supersedes the 2026-08-17 rule
  that made a staging dialog the only way to edit.** Pattern 1 for the record's own fields: the block's
  pencil turns that block into a form where it sits, with a `Cancel` and `Save` pair at the bottom of the
  block that scrolls with it. Pattern 2 for a different record referenced by this page: a modal that owns
  its own footer and its own endpoint. Pattern 3 stays too: the full edit page, reached the way Jobber
  reaches it — the client card's `...` menu, `Edit client details`, opening in a new tab.
- **A block's in-place `Save` writes to the server there and then**, like Jobber. There is no page-level
  undo for a saved block. This still satisfies the no-silent-write rule below, because the write follows a
  deliberate press of a button that says Save.
- **The footer bar stays, and it owns the page-body widgets** — tags, notes, note edits, pins, staged
  deletes. Those stage instead of writing, and the bar commits them. Because a block's own Save has already
  written, the bar has nothing left to show for that block and stays hidden. The two never compete: blocks
  save themselves, the bar saves everything that has no block of its own.
- **The bar is one component: `layout/DetailEditBar.svelte`.** Pass `dirty`, `saving`, `error`, `onSave`,
  `onCancel`; it renders nothing until `dirty`. Never hand-roll a save footer on a detail page, and never
  show a permanently visible one — a detail page is read-first, so the bar only exists while there is
  something to save. Full-page create and edit forms keep their always-visible bar through
  `RecordFormLayout`. Both draw the same `layout/StickyActionBar.svelte`.
- **What the bar stages stays written out on the page**, not hidden in a shared store: each detail page
  holds its own staged widgets, merges them over the saved record for display, and decides what one save
  means. This now covers the body widgets only — a block that edits in place saves itself and never
  reaches the draft.
- **Rebuild the payload from a fresh read of the record before saving.** Anything that saves instantly
  elsewhere on the page can otherwise be undone by a stale field in the draft's payload.
- **No write happens without the user pressing a button that saves. Jafar's rule, 2026-08-17, clarified by
  him 2026-08-18, and it overrides Jobber here** — Jobber saves tags and notes on click, and he found that
  confusing because nothing announced the write. The rule is about the button, not about which button.
  A block's in-place `Save`, a modal's own save, and the footer bar are all valid save presses. What is
  never allowed is a write that happens on a click that does not say Save: show a staged deletion struck
  through with an Undo rather than a confirm dialog, since nothing is destroyed until the save.

  The one write allowed with no save button at all is creating something shared and independent of this
  record, such as adding a brand-new tag name to the organization's catalog — the assignment still waits.

- **Editing reveals controls that reading hides**, as in the Jobber section above. Do not show
  `Add Line Item`, `Add Discount`, `Client view / Change` and their kind on a read-only block.
- **Client detail is currently the odd one out.** It was built to the superseded 2026-08-17 rule — block
  pencils open dialogs that stage into the bar, and `/clients/[id]/edit` was deleted. Jafar's call on
  2026-08-18: convert it to the rules above when we next touch that page, not as a separate job. Do not
  copy its editing shape into a new page.
- **Honest empties.** Where a domain does not exist yet, the block says what it is waiting for rather than
  showing a zero. Jobber's empty-section pattern is the model for once the domain does exist.
- **The blueprint decides which blocks exist; Jobber decides how they behave.** Where our blueprint in
  `Design/` puts a block somewhere else than Jobber does, the blueprint wins for placement. Where the
  blueprint carries a block Jobber has no equivalent for, ask Jafar — do not drop it and do not invent its
  behavior. See CLAUDE.md rule 4.
- **Component boundaries come from the tour, before any page is built.** The inventory above exists so that
  a piece shared by four screens is built once, not discovered after the fourth page.
