# C5a — The redesign checklist

**Campaign:** contractor-design-concept · **Plan:** `docs/contractor-design-concept-behavior-contract.md` § First version 3
**Stage:** Planning. Jafar approved the checklist 2026-10-18; making it has not started. Sonnet 5.5 is enough.
**Code:** a worktree and branch of your own (documents only)
**Done when:** the coverage command in `stages/list-index.md` prints nothing, every list file is 800 words or
less, and Jafar has read the list on GitHub and confirmed the order.
**Read next:** `stages/list-index.md` (key, piece format, tick rule, files, coverage command).

## Steps

- [x] Index with key, tiers and coverage command (`stages/list-index.md`).
- [ ] **List from the code.** Every page file gets a row. Every component file appears: one used by more than
  one page (directly or through another component) gets its own row in tier 1; one used in a single place goes
  in the "Inside it" cell of the page or part that uses it. Customer emails and error pages get rows. For each
  page, read its imports and inline `<Dialog`, `<Tabs`, `<DropdownMenu` use. Note its empty, loading and
  no-permission states and its owner and field-worker views. Mark each pop-up as its own drawing or 🔁 a pattern
  (the contract says which). Rows go most used first.
- [ ] **Tick what is done, from approval records only:** contract decisions and `parts/c1c` to `c3`. Known:
  - Foundation board parts are Pencil ✅.
  - Button is Built ✅; the time-clock spinner gap is in `c1e`.
  - The sidebar is Built ✅.
  - Home is Pencil ✅, Built ⬜.
  - Jobs list is ✅/✅, with its table ➖.

  Ask Jafar to open `concept.pen` and compare its boards and frames with the ticks. `classic.pen` frames are the
  old look and do not count.
- [ ] **Leave out, listed once with the reason in `list-1`:** `demo/*`, `(app)/dev-preview/*` and components only
  they use (developer pages), and phone layouts (contract "Not doing").
- [ ] **Check and hand over:**
  1. Fill the index counts.
  2. Spot check three rows against their code (Job details, Invoice details, Settings › Team).
  3. Run the coverage command.
  4. Commit, merge and push.
  5. Point NOW and the ROADMAP C5 line at `stages/list-index.md`.
  6. Delete this note.

## Next

Start "List from the code" in a new worktree, tier 1 first.
