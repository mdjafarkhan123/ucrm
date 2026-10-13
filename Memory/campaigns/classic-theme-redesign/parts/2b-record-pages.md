# 2B — Design: record pages in the new look

**Campaign:** classic-theme-redesign · **Plan:** `docs/classic-theme-redesign-behavior-contract.md` § Design
principles, § Approved additions; recipe § Record page structure
**Stage:** Design
**Code:** `classic.pen` in the main folder; commit it from main in its own commit, under a claim covering
`classic-pen`. Desktop only (plan § Desktop designs only in Pencil).
**Done when:** Jafar says yes to Job, Quote, Invoice, Request, Payment and Client details; date and names
recorded in the plan; superseded `Archive · … · first concept` frames deleted.

## Method that worked (Job, 2026-10-13)

Copy `Settings · Business profile · 1440` (`ofzTY`) for the shell, delete its page header, Body and Save bar,
then copy the archived concept's `Main and rail` frame in and remap its old `color-*` tokens to `classic2-*`
with one visitor (old → new map: job/success → green, quote → rose, request/warning → amber,
informative → blue, inactive/surface-active → chip, feature-surface → featured gradient). Sidebar active
item: override the instance's Nav item fill to `sidebar-active`, icon and label `white`, and reset
`Nav Settings`. Rail is 336 wide, so fixed-width children from the 344 concept need shrinking.

## Steps

- [x] 2026-10-13: `Job details · 1440` (`bbWOb`, x 3080 y 2300 — record pages row below Settings) drawn,
      critiqued in light and dark; app wording used (Instructions, Photos and files); client avatar violet;
      instruction icons neutral.
- [x] 2026-10-13: Jafar: v1 "did not improve the design, just converted". Agreed six upgrades ("ok"), drawn
      as `Job details · v2 · 1440` (`G2x339`, x 4620 y 2300) beside v1: Settings-style page header (job icon
      tile, crumbs, title on the page background, meta row with quick contact); clickable lifecycle track
      card (record tiles in record colours, numbers, open arrows); jump pills; dark featured card used for
      "Right now" (today's visit, Open visit, four fact chips); Close-out + Billing merged into "Ready to
      invoice?"; light team-only profit card; slimmer product rows; crew time split in the Work log.
      Light and dark checked.
- [x] 2026-10-13: Jafar kept v1's design and section placement ("I like the old design and its placement
      of section") but liked v2's record icons and numbers on the track. Applied to `bbWOb`: each step has a
      28 record tile in its record colour (request amber, quote rose, job solid green, future steps neutral),
      "Request #88" / "Quote #318" / "Job #1042" titles, a 12 open arrow on linked records. v2 deleted.
      Lesson: improve within the approved placement; don't move sections without asking.
- [x] 2026-10-13: Jafar approved `Job details · 1440` ("yes"); recorded in plan § Direction.
- [x] 2026-10-13: `Quote details · 1440` (`e5HXY`, x 4620 y 2300) drawn by copying the approved Job
      (`bbWOb`) and swapping sections, keeping the concept's placement. Main: hero (blue Awaiting
      response, Send email, record track with Quote as the current rose tile), Introduction, Products and
      services (add-on chip, discount row, locked footer + client view), Client message and disclaimer. Rail:
      profit (cost / estimated profit), Deposit, Discount and tax (the app's two rail cards shown as one),
      Automation, Photos and files, Notes. Sent quote = read-only, so no edit pencils (app `editable` needs a
      draft). Light and dark checked. Awaiting Jafar's yes.
- [ ] Invoice details (from `fPq9c`), same method — copy the Job, beside the Quote.
- [ ] Request, Payment, Client details — new; read each `+page.svelte` first (recipe § Working method 1).

## Next

Get Jafar's yes on `Quote details · 1440` (open question: one Discount and tax card vs. two cards).
Then draw Invoice from `fPq9c` by copying the approved Job, same record-icon track.
