# Sales Pipeline: Current Checkpoint

## Goal

Build one contractor-friendly commercial board from Request through Quote. Request, Assessment, and Quote
remain operational truth; Pipeline projects them and adds accountable commercial follow-up.

## Status

Parts 1–4, 5A, 5B, 5C-i, 5C-ii, and 5C-iii are all closed. Jafar verified 5C-iii's full acceptance checklist
live in the browser on 2026-08-24 and confirmed every check passes.

**Part 5D (accidental-drag recovery / Undo) is cut** — Jafar decided 2026-08-24 it isn't needed. Only
Part 6 (final A–Z audit and contractor manual) remains, and it hasn't been scoped yet.

## Exact next action

None pending. Part 6 is the only part left on this campaign but has no approved scope — propose it only
when Jafar wants to start the final audit.

## Blockers

None.

## Protected work

Keep Parts 1–4, 5A, 5B, 5C-i, 5C-ii, 5C-iii stable. Keep the `div[role="button"]` card open target; changing
it back to `button` blocks dragging in `svelte-dnd-action`. Pipeline stage/outcome and quote-backed value
remain system-owned through their existing database definers. `pipeline_drag_opportunity` stays read-only.
Request-to-Draft conversion is confirm-before-commit and terminal, with no Undo — this is now permanent
behavior, not a placeholder pending 5D.

Do not re-run the type regeneration casually: `src/lib/database.types.ts` was regenerated on 2026-08-24 and
is correct against the live schema.

`npm run test:unit` has **8 pre-existing failures** in the quotes and team specs, none from this campaign —
see `Memory/deferred/eight-vitest-failures-in-the-quotes-and-team-specs.md`. Do not chase them here.

## Required pointers

- `ROADMAP.md` — full campaign history and standing decisions, including the 5D cut.
- `docs/sales-pipeline-behavior-contract.md` — approved unified presentation and server-confirmed behavior.

## Active-part completion gate

No part is active. Part 6 starts only after Jafar approves its scope; the completion gate is written into
its packet once created.
