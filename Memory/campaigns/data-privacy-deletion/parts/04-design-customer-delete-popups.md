# Part 4 — Design: customer delete pop-ups

**Plan:** `docs/data-privacy-deletion-behavior-contract.md` § Deleting a customer, § Delete permanently now,
§ Download one customer's data. **Design rules:** `.claude/skills/design/SKILL.md`, `modals.md`, `guide.md`.
**Branch:** `claude/data-privacy-part4-design` (worktree `.worktrees/data-privacy-part4`, notes only); reservation
`3c1dc828370d`.

## Pencil board

`concept.pen` → `WEpOG` "Concept · Data privacy · Part 4 · Customer delete pop-ups · Approved B · 2026-10-24", end of
the Daily work row (x 37456, y 13392). Drawn 2026-10-24, light mode only.

- **Part 1 · Pick a look** (main Delete client pop-up):
  - A (counted tiles, 640) — not chosen, deleted.
  - B `TnUiN` — 940, "Goes" list left, sand panel right with what stays (invoices, "stop texting" fingerprint) and a
    3-step timeline (today → restore until day 30 → deleted for good); privacy delete is a quiet red footer link.
    **Approved by Jafar 2026-10-24 ("approved", after asking which I prefer).** A deleted from the board.
- **Part 2 · Every state** `PxadT`: 1 money still open (refusal, Open buttons) · 2 delete permanently now with the
  typed name (typing, deleting) · 3 receipt (deleted counts; kept and why; Copy receipt) · 4 many clients at once
  (on B; clients with open money left out and named) · 5 counting, couldn't count, deleting, couldn't delete (on B)
  · 6 Download client data pop-up · 7 preparing / ready / couldn't prepare toasts and the bell row.

## Choices I made that go beyond the plan (flag to Jafar)

- Bulk delete leaves out clients with open money and names them, instead of refusing all.
- After delete: a toast with Undo ("moved to Recently Deleted").
- The "stop texting" card shows only when the client opted out of something.
- Toasts have no approved concept design yet; drawn here for the first time.

## Next action

Look recorded in `.claude/skills/design/modals.md` § Delete client pop-ups. `concept.pen` saved and committed
to main 2026-10-24 (`35b3a064`, with the earlier session's unsaved changes, Jafar "ok commit"). Builds in Part 6 (delete and
restore), 7 (delete now, receipt) and 10 (download). Pencil tidy-up after the build.
