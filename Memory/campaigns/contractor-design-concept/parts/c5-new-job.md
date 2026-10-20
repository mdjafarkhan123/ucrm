# C5 — New job in the concept

**Campaign:** contractor-design-concept · **Plan:** `docs/contractor-design-concept-behavior-contract.md` § First version 3
**Stage:** **Approved by Jafar 2026-10-18** ("approved"), including the four new parts below. Frames in `concept.pen`: New job `zUFDO`, Other states
`TVQzs` (from a request, recurring). **Done when:** Jafar approves; record his yes and date here.
**Live page:** `src/routes/(app)/jobs/new/+page.svelte` → `src/lib/components/jobs/JobForm.svelte`,
`JobVisitsBlock.svelte`, `RecurrenceFields.svelte`.

## Research

Jobber's job form: client and property, title, one-off or recurring (type cannot change after saving), visits that
are timed, anytime or unscheduled, team per visit, line items, "remind me to invoice when I close the job" for
one-off work (`.claude/skills/jobber/jobber-04-jobs-visits-scheduling.md` §2, §3.4, §5).

## What is drawn (all live fields kept, nothing new added)

- Page header: 40 job tile, "New job", one-line description; a Job # pill "Given when you save" replaces today's
  read-only Job # field.
- Main column: **The job** (title, picked client box from Job details with Change client, job property row with
  Change property) → **Products and services** (the `jFBRB` edit block without discount, tax and its own save bar;
  Job subtotal box and the note "Discount and tax are added on the job once it is saved") → **Visits** (One-off /
  Recurring switch, one visit open for editing, one folded, people as pick chips, Notify customer) → **Billing**
  (invoice-on-close tick).
- Rail: the deep-green Job total card listing the lines and the subtotal.
- A floating save bar at the foot: "New job · not saved yet", Cancel, Save job.
- Other states: request banner + locked client ("From the request"); recurring schedule with visit count and the
  billing note.

## New parts (approved with the screen)

Segmented switch, checkbox, people pick chips, floating save bar. Not yet on the Parts board or in the design
skill modules.

## Next

Built third in `parts/c7-build-pilots.md`; its four new parts go onto the Parts board, the design modules and
code during that build.

## Batch 31 — whole New job page from scratch (Jafar 2026-10-20)

Jafar: redesign the whole New job page from scratch as an improved Jobber, following `design/guide.md`. Keep a
right rail (Jobber has none). The header is one card in the main column like the record header, never over the rail.
Approved new behaviour: "+ Create new client" inside the client list (from Jobber).

Jobber live tour (trial, 2026-10-20, /jobs/new): one white top panel with a green top line, hammer + "New Job",
full-width Title, "Select a client" combobox (list rows: name, address, email · phone, Active/Sample pill; foot
"+ Create new client"); picked → client card (name, address, phone, email links; "…" menu: View client profile,
Edit client details, Change property, Change client in red). Right of it: Job # (prefilled, editable), Customize ·
Add Field. Then Visits (One-off/Recurring, "1 visit", Create Visits; visit: title, date, Schedule later, start/end,
Anytime, Assigned chips, Visit instructions; checklists prompt; Email team about assignment; Add a Visit, Reset),
Billing (Remind me to invoice when I close the job; Split into multiple invoices with a payment schedule),
Product / Service (name, qty, unit cost, unit price, total, description; Add Line Item; Subtotal, Discount, Tax,
Total price, Total cost), Notes (dashed empty box). Sticky foot: Cancel, Save Job split (Save and… Create Another,
Email Booking Confirmation).

Drawn 2026-10-20, waiting for Jafar's pick: board `M0VXo` "Concept · Batch 31 · New job page · A vs B".
A Job header card (green top with New job, Job # pill and the big title field; client on the white part; then
Products and services, Visits, Billing, Notes; rail keeps the deep-green Job total). B Steps and a live summary
(light header with a four-step track Client · Work · Visits · Billing; "Who it is for" card; rail is a Job summary
card — client, the work, visits, team, invoicing — with the deep-green total at its foot). Shared: "Choosing a
client" strip (page opens, typing with list and "+ Create new client", nobody matches) and dark mode.
On approval: replace `zUFDO` and `TVQzs`, update `layout.md` → Create pages, delete the unchosen option.

## One create page for all four (Jobber live tour, 2026-10-20)

Jobber's /requests/new, /quotes/new, /jobs/new and /invoices/new are one shared page frame. Same: white top
panel with a coloured top line (Request orange, Quote red, Job green, Invoice blue), type icon + "New X", a
full-width Title (Invoice: "Subject", prefilled "For Services Rendered"), "Select a client" on the left, a
label/value list on the right, then section cards, a Product / Service block, Notes (dashed empty box), and the
sticky foot Cancel + "Save X" (split menu on Quote/Job/Invoice, plain on Request).
Right-hand list: Request — Requested on (today); Quote — Quote #, Customize · Add Field; Job — Job #,
Customize; Invoice — Invoice #, Issued date (Date Sent), Payment terms (Due upon receipt), Customize.
Body per type: Request — Overview (Service details, images), On-site assessment, Product / Service (simple,
Subtotal/Total), Notes. Quote — "+ Add section" chips (Introduction; later Attachments, Images, Client
Message), Product / Service with Mark as optional, image, Add Line Item / Add Text, Client view, Subtotal,
Discount, Tax, Total, Add Deposit or Payment Schedule; Contract / Disclaimer (Apply to all future quotes);
Notes. Job — Visits, Billing, Product / Service, Notes. Invoice — Product / Service with Add Service Date,
Invoice Totals (Client view, Subtotal, Discount, Tax, Total, Invoice balance), Add section (Client Message,
Contract / Disclaimer), Images, Attachments, Notes.

Our code already shares most of this: all four forms use RecordFormLayout, SectionBlock, ClientPicker and
ProductsAndServicesBlock; Request, Quote and Invoice use PrimaryInfoCard, but JobForm draws its own header
(PickedClient, IconTile). Proposal to Jafar: draw one shared "Create page" in Pencil, and let the Batch 31
A/B pick decide its look for all four.

Jafar decided (2026-10-20): the four create pages (Request, Quote, Job, Invoice) follow Jobber's shared frame,
plus our own right sidebar. Products/services and visits use our approved components. Jobber's top panel
(title, client, facts list) is redesigned new: like Jobber's, but improved, following `design/guide.md`.
Jafar (2026-10-20): every part the live create forms already have stays, in the same place (main column or
right sidebar). Live today — Request: main = header card (client), Service overview, On-site assessment,
Products; sidebar = Notes, Attachments. Quote: main = header card (client, property, Quote #), Introduction
(add-section), Products + Client view, Client message (add-section), Contract disclaimer; sidebar = Quote
total, Discount, Tax, Notes, Attachments. Job: main = The job (title, client, property), Products, Visits
(+ notify customer), Billing; sidebar = Job total. Invoice: main = header card (client, service property,
Invoice #), Products, Terms & dates (invoice date, payment terms, due date); sidebar = Invoice total,
Attachments. Only the top panel gets the new look.
Jafar (2026-10-20): the Batch 31 New job board is not needed; we start new with one shared create page. Board
`M0VXo` was already gone from concept.pen when checked. Still on the canvas: `zUFDO`, `TVQzs` (old New job) and
`U8RY1n` (Batch 25 First block on New forms, approved earlier today); asked Jafar whether these go too.

Drawn 2026-10-20, waiting for Jafar's pick: board `KiMYd` "Concept · Batch 31 · Create pages · A vs B". Each
option: a full New job page (copy of `zUFDO`, its page header and "The job" card swapped for the new top panel;
everything else as approved), the panel on New request, quote, invoice and an empty New job, and dark mode.
A Record header, in draft (coloured top with tile, "New job", Draft pill and a big title box; client line with
Change client; facts row: number "Given when you save" + Edit, property + Change). B Split sheet from Jobber
(4px record-colour line, Card header, title + client card with property strip on the left, a 248 "Details"
panel on the right: number box, Requested on for requests, Status "Draft until you save").
On approval: delete the unchosen option, `zUFDO`, `TVQzs` and `U8RY1n`; update `layout.md` → Create pages.

Jafar (2026-10-20): `KiMYd` did not follow Jobber — a create page is a form (empty fields to type and pick), not
a details page; follow Jobber's section order (job: top panel, Visits, Billing, Products). Board `KiMYd` deleted.
Redrawn as board `OVzkZ` "Concept · Batch 31 · Create pages · A vs B", same layout in both, look differs:
top panel = Title box full width; under it the Client search box (left) and the record's own fields (right:
Job # / Quote # / Requested on / Invoice # + Issued date + Payment terms, as Jobber). A calm white (4px record
line, tile + name, label-and-box rows); B tinted head in the record colour, fields on a soft panel with tiles.
Each: full New job page as it opens (Visits, Billing, Products order; rail unchanged), the panel on all four
pages, "Choosing a client" (typing list + Create new client, nobody matches, picked card with … menu), dark mode.
Invoice's issued date and payment terms move into the panel (Jobber); our Terms & dates card would go.

## Create form header polish (2026-10-20)

Jafar: the approved shared header (`m4ibfF`, `pM2Vf`, `el2At`) may need a polish or small redesign; refine, at
least two options, use the approved field, tile and other small parts (no custom boxes). Drawn, waiting for
Jafar's pick: board `NhVGQ` "Concept · Batch 31 · Create form header polish · A vs B". Same placement as approved.
A Quiet white, polished (soft linear wash of `--color-<record>--surface` into white behind the heading, white 40
tile, 4px record line kept, tighter heading). B Coloured top like the Record header (record surface top holds the
heading and the Title field; client and the record's field on white below). Both: request in the page above
Service overview, job / quote / invoice, dark mode. Required stars 13/700 per `inputs.md`.
On approval: delete the unchosen option and update `layout.md` → Create pages. Note: the approved look's
layout.md text is on the Codex branch (`f65583bc`), not yet on main.
