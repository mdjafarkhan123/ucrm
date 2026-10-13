# 2 — Design: record page family

**Campaign:** classic-theme-redesign · **Plan:** `docs/classic-theme-redesign-behavior-contract.md` § Design
principles, § Direction agreed so far
**Stage:** Design
**Code:** `classic.pen` in the main folder (Pencil saves there); commit it from main in its own commit, under a
claim covering `classic-pen`.
**Done when:** Jafar says yes to the named screens; date and names recorded in the plan.
**Read next:** `.claude/skills/design/SKILL.md` § Design in Pencil first, then `design-classic`; the Pencil
MCP's own skill and `execute.md`; each page's `src/routes/(app)/<record>/[id=uuid]/+page.svelte` for its real
sections.

## Steps

- [ ] Switch every text node in `Job details · Claude concept · Job cockpit · 1440` (frame `oNoOG`, including
      its sidebar and top-bar copies) from Plus Jakarta Sans to Inter; re-check nothing clips
- [ ] Add the concept's new colours, 20px card corner and shadow to the Classic design-system page as named
      tokens with light and dark values, then point the job concept at them
- [ ] Design the quote and invoice pages from the same parts; show Jafar them beside the job page
- [ ] Design a Settings page with the new cards
- [ ] Design the request, payment and client pages
- [ ] Record Jafar's yes, the date and the screen names in the plan

## Next

Start the first step. Before any `classic.pen` change, check `agent-work.py list`; another agent may hold
`classic-pen`. Ask Jafar to press Ctrl+S in Pencil before committing — Pencil does not write to disk on its own.

## Notes

- Hard-coded values in the concept to turn into tokens: page `#F3F2EE`; card border `#E4E2DC`; row dividers
  `#ECEAE5`; today-row tint `#F5FAF6`; profit card on `$color-surface-reverse` with segments `#3B9AE8`,
  `#F0A44B`, `#84CC16` and chip `#FFFFFF14`; card shadows `0 1 2 #032B3A0A` and `0 12 32 #032B3A0D`.
- Pencil `execute` globals did not persist between calls on 2026-10-13; use literal node ids.
- The concept's header facts, visits, line items, work log, profit, close-out, billing, instructions, photos
  and notes show the layout pattern for the other pages; each page keeps its own real sections.
