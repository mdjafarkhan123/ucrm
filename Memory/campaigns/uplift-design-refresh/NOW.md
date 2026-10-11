# Uplift design refresh — now

**Goal:** A premium, modern, polished, colourful CRM, delivered through small demos Jafar reviews before implementation.
**Plan:** `docs/uplift-design-refresh-behavior-contract.md`

**State:** In progress 2026-10-11. Only sidebar variant 2 revision 2 is approved. Jafar corrected the inferred header approval and requested another visible design before choosing. Live components remain unchanged.

**Next:** Present `/demo/header-option-b/index.html` alongside the original header at `/demo/app-shell-v2/index.html`. Wait for Jafar’s choice and explicit approval, then align header guidance and close Part 3. Read `parts/3.md` and `docs/design/botanical-v3/sidebar-approval.md` for scope.

**Maintenance rule:** Keep the existing design skill and update necessary parts incrementally. Use `.claude/skills/design/alignment.md` as the reading gate: load only modules explicitly updated for the relevant redesign coverage; uncovered patterns need a focused demo, not old visual guidance. Update each relevant module after its focused demo is built and approved, before implementation.

**Reference:** `docs/design/botanical-v3/` preserves desktop/phone captures and rendered evidence. The preview requests Inter but rendered a fallback font. Phone navigation is absent in the reference; resolve it in Part 3, not by silently approving the existing phone layout.

**Remaining checks:** Corroborate the real signed-in shell, text resizing and shared-page impact before implementation. New designs outside the approved scope still need review.
