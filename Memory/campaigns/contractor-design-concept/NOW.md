# Contractor design concept — now

**Goal:** A new design concept for the whole app, drawn in `concept.pen` from the app's own variables: design → review → approve → build.
**Core agreement — read on every resume:** `docs/contractor-design-concept-behavior-contract.md` (Summary, First version, Not doing, decisions) and the design skill `.claude/skills/design/SKILL.md` with its modules.
**Stage:** Designing. C1 Foundation approved 2026-10-17 (`concept.pen` boards "Colour that means something" and "The parts every screen is built from").

**Next:**
0. Button set (`c1b-button-set`, branch `claude/concept-buttons`): drawn in Parts → "Buttons", rules in `buttons.md`. Waits for Jafar's review and Ctrl+S; then commit `concept.pen` on the branch and merge. Live `Button` greys out while loading; the concept keeps its colour — change it with the first built screen.
1. In `concept.pen`, add number variables for text 11, 13, 32; tile corners 6 and 10; card padding 20, and bind the Foundation nodes using them. Name them in the app's style (e.g. `typography--fontSize-label`, `radius-tile--small`, `space-medium`); update the matching modules in the same commit. Code gets them, plus `shadow-button` and `shadow-button--raised` (`shadows.md`), with the first built screen.
2. C2 Home: research what a contractor needs on Home (Jobber first), draw at 1440 from the Foundation parts, show Jafar.

**Working notes:** Pencil edits only the open file and writes only on Ctrl+S (`docs/pencil-workflow.md`).

**Still open:** rollout (all at once or screen by screen); money cards in dark mode; "Changes requested" colour; whether to keep two styling-module sets after rollout.
