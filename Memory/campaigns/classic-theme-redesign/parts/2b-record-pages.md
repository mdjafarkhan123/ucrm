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

- [x] 2026-10-13: `Job details · 1440` (`bbWOb`, x 3080 y 2300) approved after one rejected rearranged v2.
      Lesson: improve within the approved placement; don't move sections without asking. Details: plan § Direction.
- [x] 2026-10-13: `Quote details · 1440` (`e5HXY`, x 4620) and `Invoice details · 1440` (`dQ7vH`, x 6160),
      both y 2300, drawn by copying the approved page and swapping sections; approved (plan § Direction).
      Read-only states show no pencils (follow the page's `editable` rules); the app's Discount and Tax
      cards show as one "Discount and tax" card.
- [x] 2026-10-13: Jafar approved Invoice and chose the Jobber-style green card for all pages, with brighter
      text; tokens updated in Pencil and the recipe, variant board deleted (plan § Direction).
- [ ] Request, Payment, Client details — new; read each `+page.svelte` first (recipe § Working method 1).

## Next

Request, Payment, Client details (fresh session): read each real `+page.svelte` first, copy the approved
Job/Quote/Invoice shell, keep the record-icon track and the green summary card at the top of the rail.
Then delete the `Archive · … · first concept` frames and mark 2B Done.
