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
