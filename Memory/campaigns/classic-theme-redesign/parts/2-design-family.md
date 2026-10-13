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

- [x] Switch every text node in `Job details · Claude concept · Job cockpit · 1440` (frame `oNoOG`, including
      its sidebar and top-bar copies) from Plus Jakarta Sans to Inter; re-check nothing clips — done
      2026-10-13, all 216 texts use `$font-family`
- [x] Add the recipe's raw values (colours, 20px card corner, shadows) to the Classic design-system page as
      named tokens with light and dark values; point the job concept and the recipe at the token names —
      done 2026-10-13: 23 tokens; Card part, Button part (`$radius-control`, primary glow) updated to match
      (Jafar: "if new design require to change any design system we will do it to match")
- [ ] Design the quote and invoice pages from the same parts; show Jafar them beside the job page — drawn
      2026-10-13 (`Quote details · Classic redesign · 1440`, `Invoice details · Classic redesign · 1440`,
      right of the job screen); job track and wording aligned to them; shown to Jafar, waiting on his reaction
- [ ] Design a Settings page with the new cards
- [ ] Design the request, payment and client pages
- [ ] Record Jafar's yes, the date and the screen names in the plan

## Next

Read Jafar's reaction to the quote and invoice screens and apply it to all three. Layout moves he should
confirm: invoice Terms & dates folded into the key facts strip (pencil); discount and tax as rows in the
totals block; quote photos moved to the rail; History card tabs on the invoice. Then design Settings. Before
any `classic.pen` change, check `agent-work.py list`; ask Jafar to press Ctrl+S in Pencil before committing.
