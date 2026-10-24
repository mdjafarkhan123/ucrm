# Part 5 — Design: Recently Deleted page

**Plan:** `docs/data-privacy-deletion-behavior-contract.md` § Deleting a customer (Recently Deleted, restore, day 30).
**Design rules:** `.claude/skills/design/SKILL.md`, `guide.md`, `layout.md`, `cards.md`, `badges.md`, `lists.md`.
**Branch:** `claude/data-privacy-part5-design` (worktree `.worktrees/data-privacy-part5`, notes only); reservation
`4908c90fda0b`.

## Research (2026-10-24)

- HubSpot restore page: from the index ⋯ menu; tick boxes, select all in a date range, Restore with a count
  confirm; date filter; restore blocked while an active contact has the same email.
- HighLevel: Contacts ⋯ → Restore; columns name, email, phone, deleted on; a Restore per row and bulk ticks.
- Google Drive / Apple Photos trash: days left shown on each item.

## Pencil board

`concept.pen` → `Wf0tP` "Concept · Data privacy · Part 5 · Recently Deleted page · Approved B · 2026-10-24", end of
the Daily work row (x 38796, y 13392). Built from the Jobs list page (`t8ULdJ`), Clients active in the sidebar.

- **Part 1 · Approved B · Countdown** `ih9b2` (screen `f243Uk`). **Approved by Jafar 2026-10-24 ("B").** A · Restore
  table deleted from the board.
- **Part 2 · Every state** `fhrR3`: 1 picking several + floating bar · 2 row ⋯ menu (Restore; Delete permanently
  now → Part 4 pop-up) · 3 restoring, restored and failed toasts · 4 newer client with the same phone → Restore and
  merge / Restore as a separate client · 5 empty, loading, couldn't load, search no match.

## Choices beyond the plan (flag to Jafar)

- Restore many at once (HubSpot, HighLevel) — the plan names restore, not bulk restore. Restore has no "are you
  sure?" step.
- No "Empty trash" button: delete now stays one client at a time (plan).
- Many at once with a phone/email match: restored separately and named in the toast.

## Next action

Look recorded in `.claude/skills/design/layout.md` § Recently deleted page. Waiting for Jafar to save
`concept.pen` (Ctrl+S); then commit it in its own commit and merge the branch. Builds in Part 6. Pencil tidy-up
after the build.
