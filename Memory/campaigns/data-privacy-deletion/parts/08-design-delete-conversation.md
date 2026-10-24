# Part 8 — Design: delete conversation pop-up

**Plan:** `docs/data-privacy-deletion-behavior-contract.md` § Deleting a conversation. **Design rules:**
`.claude/skills/design/SKILL.md`, `modals.md`, `inbox.md`, `guide.md`, `layout.md` § Recently deleted page
(picking several). **Branch:** `claude/data-privacy-part8-design` (worktree `.worktrees/data-privacy-part8`, notes
only); reservation `671dbf79f012`.

## Pencil board

`concept.pen` → `x3ov1D` "Concept · Data privacy · Part 8 · Delete conversation pop-ups · Pick A or B · 2026-10-24",
end of the Communications row (x 18924, y 39655). No inbox pop-up board existed, so this starts one. Light only.

- **Part 1 · Pick a look** (`jXmvC`): A `es9gr` short and counted (600: red notice, one counted list box, two
  "stays" lines, plain radio reason + note) · B `FRzrQ` your side, their side (640: red "your team's inbox" panel
  vs teal "Daniel's side" panel, sand "stays a client" strip, 2×2 reason tiles, log note in the footer).
- **Part 2 · Where it starts** (`jockt`): ⋯ menu with Delete conversation last under a line, absent without the
  permission; list picking (hover tick box, 3 picked, 100 limit) reusing the Recently Deleted picking pattern.

## Choices beyond the plan (flag to Jafar)

- The reason is a choice of four (asked us / spam or wrong number / sent by mistake / something else + note).
- List tick boxes and a floating bar are new to the inbox (plan approves bulk delete of up to 100).
- Live chat header has no ⋯ menu yet; the concept's ⋯ ("Mark as unread") gets Delete under a line.

## Next action

Waiting for Jafar to pick A or B. Then: delete the unchosen option, draw states on the chosen look (deleting,
couldn't delete, many at once, toast), record the look in `modals.md`, Jafar saves concept.pen, commit it.
