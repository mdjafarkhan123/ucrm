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
      instruction icons neutral. Waiting on Jafar's review.
- [ ] Quote details (from `Ae1NJ`) and Invoice details (from `fPq9c`), same method, beside the Job.
- [ ] Request, Payment, Client details — new; read each `+page.svelte` first (recipe § Working method 1).

## Next

Wait for Jafar's answer on `Job details · 1440`; apply changes, then Quote and Invoice.
