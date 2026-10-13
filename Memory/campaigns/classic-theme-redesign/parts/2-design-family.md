# 2 — Design: record page family

**Campaign:** classic-theme-redesign · **Plan:** `docs/classic-theme-redesign-behavior-contract.md` § Design
principles, § Direction agreed so far
**Stage:** Design
**Code:** `classic.pen` in the main folder (Pencil saves there); commit it from main in its own commit, under a
claim covering `classic-pen`.
**Done when:** Jafar says yes to the named screens; date and names recorded in the plan.
**Read next:** `docs/classic-theme-redesign-design-recipe.md` — its working method governs every step below;
`.claude/skills/design/SKILL.md` § Design in Pencil first, then `design-classic`; the Pencil
MCP's own skill and `execute.md`; each page's `src/routes/(app)/<record>/[id=uuid]/+page.svelte` for its real
sections.

## Steps

- [ ] Switch every text node in `Job details · Claude concept · Job cockpit · 1440` (frame `oNoOG`, including
      its sidebar and top-bar copies) from Plus Jakarta Sans to Inter; re-check nothing clips
- [ ] Add the recipe's raw values (colours, 20px card corner, shadows) to the Classic design-system page as
      named tokens with light and dark values; point the job concept and the recipe at the token names
- [ ] Design the quote and invoice pages from the same parts; show Jafar them beside the job page
- [ ] Design a Settings page with the new cards
- [ ] Design the request, payment and client pages
- [ ] Record Jafar's yes, the date and the screen names in the plan

## Next

Start the first step. Before any `classic.pen` change, check `agent-work.py list`; another agent may hold
`classic-pen`. Ask Jafar to press Ctrl+S in Pencil before committing — Pencil does not write to disk on its own.

