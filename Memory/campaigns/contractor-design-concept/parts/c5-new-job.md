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
