# Part 4 — Design: customer delete pop-ups

**Plan:** `docs/data-privacy-deletion-behavior-contract.md` § Deleting a customer, § Delete permanently now,
§ Download one customer's data. **Design rules:** `.claude/skills/design/SKILL.md`, `modals.md`, `guide.md`.
**Branch:** `claude/data-privacy-part4-design` (worktree `.worktrees/data-privacy-part4`, notes only); reservation
`3c1dc828370d`.

## Pencil board

`concept.pen` → `WEpOG` "Concept · Data privacy · Part 4 · Customer delete pop-ups · To review · 2026-10-24", end of
the Daily work row (x 37456, y 13392). Drawn 2026-10-24, light mode only.

- **Part 1 · Pick a look** (main Delete client pop-up):
  - A `nwVl7` — 640, counted record tiles (Merge clients family), a blue "stays" strip, two radio tiles: Recently
    Deleted / Delete permanently now.
  - B `TnUiN` — 940, "Goes" list left, sand panel right with what stays (invoices, "stop texting" fingerprint) and a
    3-step timeline (today → restore until day 30 → deleted for good); privacy delete is a quiet red footer link.
    **Recommended.**
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

Wait for Jafar to pick A or B (or a mix). On his yes: record it here, delete the unchosen option, retitle the board
"Approved", ask him to Ctrl+S, then commit `concept.pen` under a claim. Note: main's `concept.pen` already had
uncommitted changes from an earlier session (modified 2026-10-23 23:19) before this board; check with Jafar before
committing it together.
