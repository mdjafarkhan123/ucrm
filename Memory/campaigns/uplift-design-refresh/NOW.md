# Uplift design refresh — now

**Goal:** A premium, modern, polished, colourful CRM, delivered through small demos Jafar reviews before implementation.
**Plan:** `docs/uplift-design-refresh-behavior-contract.md`

**State:** Paused 2026-10-11. Sidebar and header variant 2 revision 2 approved; demo saved and pushed. Live components remain unchanged.

**Next:** Finish Part 3’s header guidance alignment, then prepare Part 4’s shared-shell impact and implementation checks. No further variant is requested. Read `parts/3.md` and `docs/design/botanical-v3/sidebar-approval.md` for approval scope and remaining verification.

**Maintenance rule:** Keep the existing design skill and update necessary parts incrementally. Use `.claude/skills/design/alignment.md` as the reading gate: load only modules explicitly updated for the relevant redesign coverage; uncovered patterns need a focused demo, not old visual guidance. Update each relevant module after its focused demo is built and approved, before implementation.

**Reference:** `docs/design/botanical-v3/` preserves desktop/phone captures and rendered evidence. The preview requests Inter but rendered a fallback font. Phone navigation is absent in the reference; resolve it in Part 3, not by silently approving the existing phone layout.

**Remaining checks:** Corroborate the real signed-in shell, text resizing and shared-page impact before implementation. New designs outside the approved scope still need review.
