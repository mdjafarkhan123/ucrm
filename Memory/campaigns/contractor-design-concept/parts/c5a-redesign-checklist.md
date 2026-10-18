# C5a — The redesign checklist

**Campaign:** contractor-design-concept · **Plan:** `docs/contractor-design-concept-behavior-contract.md` § First version 3
**Stage:** Made 2026-10-18 and coverage-clean (`stages/list-index.md`). Waiting for Jafar to read it and confirm the order, the pop-up marks and the Pencil ticks.
**Code:** documents only (branch `claude/c5a-redesign-checklist`)
**Done when:** the coverage command in `stages/list-index.md` prints nothing, every list file is 800 words or
less, and Jafar has read the list on GitHub and confirmed the order.
**Read next:** `stages/list-index.md` (key, piece format, tick rule, files, coverage command).

## Steps

- [x] Index with key, tiers and coverage command (`stages/list-index.md`).
- [x] **List from the code.** Every page file gets a row. Every component file appears: one used by more than
  one page (directly or through another component) gets its own row in tier 1; one used in a single place goes
  in the "Inside it" cell of the page or part that uses it. Customer emails and error pages get rows. For each
  page, read its imports and inline `<Dialog`, `<Tabs`, `<DropdownMenu` use. Note its empty, loading and
  no-permission states and its owner and field-worker views. Mark each pop-up as its own drawing or 🔁 a pattern
  (the contract says which). Rows go most used first.
- [x] **Tick what is done, from approval records only** (the "ask Jafar" half is still open): contract decisions and `parts/c1c` to `c3`. Known:
  - Foundation board parts are Pencil ✅.
  - Button is Built ✅; the time-clock spinner gap is in `c1e`.
  - The sidebar is Built ✅.
  - Home is Pencil ✅, Built ⬜.
  - Jobs list is ✅/✅, with its table ➖.

  Ask Jafar to open `concept.pen` and compare its boards and frames with the ticks. `classic.pen` frames are the
  old look and do not count.
- [x] **Leave out, listed once with the reason in `list-1d-left-out.md`:** `demo/*`, `(app)/dev-preview/*` and components only
  they use (developer pages), and phone layouts (contract "Not doing").
- [ ] **Check and hand over:**
  1. [x] Fill the index counts.
  2. [x] Spot check three rows against their code: Job details, Invoice details and Settings › Team match their imports and pop-ups.
  3. [x] Run the coverage command: prints nothing.
  4. [ ] Commit, merge and push (in progress).
  5. [ ] Jafar reads the list on GitHub and confirms the order; he compares the Pencil ticks with `concept.pen`.
  6. [ ] Then point NOW and the ROADMAP C5 line at the first list file to draw, and delete this note.

## Choices made while listing (tell Jafar)

- Parts used only by Settings/Setup or only by the admin panel sit first in those tiers, not in tier 1.
- Pop-up marks are a first guess from titles; see the index.
- Pencil ticks: foundation parts Pencil ✅ (Badge, StatusBadge, Input, Select, Textarea, Card, Topbar); not checked
  against `concept.pen` yet. Requests/Quotes/Invoices/Clients lists 🔁/🟡 (shared cards and header built).

## Next

Wait for Jafar's read. Then C4 Job details.
