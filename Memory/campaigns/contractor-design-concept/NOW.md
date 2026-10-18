# Contractor design concept — now

**Goal:** A new design concept for the whole app, drawn in `concept.pen` from the app's own variables: design → review → approve → build.
**Core agreement — read on every resume:** `docs/contractor-design-concept-behavior-contract.md` (Summary, First version, Not doing, decisions) and the design skill `.claude/skills/design/SKILL.md` with its modules.
**Stage:** Designing. C1 Foundation approved 2026-10-17 (`concept.pen` boards "Colour that means something" and "The parts every screen is built from").

**Next:**
1a. **Buttons everywhere: built and merged into main 2026-10-18** (`parts/c1e-buttons-everywhere.md`). Still to do: format, lint and type check on the ~130 changed files (deferred to campaign end by Jafar); the time-clock Stop/Clock out buttons show text instead of the spinner; a compact on/off look for editor toolbars (QuoteTermsEditor) is not designed.
1. In `concept.pen`, add number variables for text 11, 13, 32; tile corners 6 and 10; card padding 20, and bind the Foundation nodes using them. Name them in the app's style (e.g. `typography--fontSize-label`, `radius-tile--small`, `space-medium`); update the matching modules in the same commit. Code gets them with the first built screen.
2. C2 Home: research what a contractor needs on Home (Jobber first), draw at 1440 from the Foundation parts, show Jafar.

**Working notes:** Pencil edits only the open file and writes only on Ctrl+S (`docs/pencil-workflow.md`).

**Still open:** rollout (all at once or screen by screen); money cards in dark mode; "Changes requested" colour; whether to keep two styling-module sets after rollout.
