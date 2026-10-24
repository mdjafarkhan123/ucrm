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

`concept.pen` → `Wf0tP` "Concept · Data privacy · Part 5 · Recently Deleted page · Pick a look · 2026-10-24", end of
the Daily work row (x 38796, y 13392). Built from the Jobs list page (`t8ULdJ`), Clients active in the sidebar.

- **A · Restore table** `QXZUO` (screen `LC3Ed`): breadcrumb, informative day-30 notice, table with ticks, client,
  what went (+ invoices kept), deleted by, deleted, days-left pill (red ≤3, yellow ≤7), Restore and ⋯.
- **B · Countdown** `ih9b2` (screen `f243Uk`): red "Deleted for good this week" card, then "Can still be restored";
  rows with a days ring, coloured counts of what comes back, the go date, Restore and ⋯; side column with the
  30-day timeline and "Always kept" (invoices, stop-texting choices, See kept invoices).

## Choices beyond the plan (flag to Jafar)

- Restore many at once (HubSpot, HighLevel) — the plan names restore, not bulk restore.
- No "Empty trash" button: delete now stays one client at a time (plan).

## Next action

Waiting for Jafar to pick A or B. Then: delete the unchosen option, draw every state on the chosen look (tick
several + bar, restoring, restored toast, newer client shares phone/email → Merge or Restore as separate, ⋯ menu
with Delete permanently now opening Part 4's pop-up, empty, loading, couldn't load, search no match), ask Jafar
to save, commit concept.pen, record the look in `modals.md`/`layout.md`.
