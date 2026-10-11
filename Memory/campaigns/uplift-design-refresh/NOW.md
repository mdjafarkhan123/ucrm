# Uplift design refresh — now

**Goal:** A premium, modern, polished, colourful CRM, delivered through small demos Jafar reviews before implementation.
**Plan:** `docs/uplift-design-refresh-behavior-contract.md`

**State:** In progress 2026-10-11. Sidebar v2 revision 2 approved. Jafar prefers Carbon-inspired header B with a circular avatar; revision 2 applies it. Desktop web is the primary target. Background discussion and final header review remain open. Live components unchanged.

**Next:** Review `/demo/header-option-b/index.html` revision 2 with Jafar, clarify which current background he means, and settle desktop background/header approval. Botanical reference and header B desktop images were inspected; a fresh signed-in app comparison has not been done. Then align approved header guidance and close Part 3.

**Maintenance rule:** Keep the existing design skill and update necessary parts incrementally. Use `.claude/skills/design/alignment.md` as the reading gate: load only modules explicitly updated for the relevant redesign coverage; uncovered patterns need a focused demo, not old visual guidance. Update each relevant module after its focused demo is built and approved, before implementation.

**Reference:** `docs/design/botanical-v3/` preserves desktop/phone captures and rendered evidence. The preview requests Inter but rendered a fallback font. Phone navigation is absent in the reference; resolve it in Part 3, not by silently approving the existing phone layout.

**Remaining checks:** Corroborate the real signed-in shell, text resizing and shared-page impact before implementation. New designs outside the approved scope still need review.
