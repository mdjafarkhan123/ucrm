# Settings variant B — comparison proposal

**State:** Drawn, waiting for Jafar's comparison. No approval or application rollout implied.
**Branch/worktree:** `codex/settings-variant`, `/tmp/ucrm-settings-variant`.
**Claim:** `00c5f9672d3e`, area `classic-pen-settings-variant` (new nodes only).

Jafar requested an alternative to Claude's Taxes and Checklists samples on 2026-10-17.
The shared `classic.pen` was already modified when this work started; existing edits and
`src/lib/styles/_variables.scss` were left alone. The canvas now contains two additional frames
at y=19357: Taxes `dPdYI`, Checklists `N7x4v`, x=0 and x=1540. Originals unchanged.

## Proposed visual choices

- Taxes: rates table beside a green business-default panel, percentage and Change default prominent;
  Add tax rate in the header. No summary counts. Default row lightly highlighted.
- Checklists: two columns, names first, question counts secondary, required count as plain text,
  answer types without individual chips, archived entry in a quieter full-width row.
- Existing shell, buttons, badges, tiles, colours and typography reused. No new behaviour.
- Tax wording follows `docs/contractor-settings-blueprint.md`, Taxes: property-specific settings
  take precedence. Sample checklist information matches the original canvas.

## Evidence and limits

Pencil screenshots inspected twice at 1440 × 1024: both frames fit, without visible overflow.
Desktop-only scope follows the campaign agreement. Static visual proposal; no live-app changes,
keyboard proof or usability test. Pencil's structural clipping visitor reported false positives
for fully visible Checklists children; screenshots were the visual check.

PNG exports at 2× are in `design-previews/settings-variant/`, committed for recovery. The shared
`.pen` file is not included in this branch because it contained another writer's unsaved work.
Preserve these two nodes in the next coordinated shared-canvas save. No approval has been recorded.

**Next:** Jafar compares the two variants. Only implement or expand a chosen direction after his decision.
