# Contractor Settings: Current Checkpoint

## Goal

Give contractors one permission-aware control room for business identity and feature-owned settings.

## Where things stand

Part 4B-2c (booking builder screens) closed 2026-09-13 — code-complete, browser-verified on Raad LTD, and
committed. Details live in ROADMAP.md's 4B-2c entry. That pass also found and fixed two real bugs along the
way: a `create_form` regression that broke all new-form creation, and a missing app-side worker for the
organization geocoding queue (Service area radius still won't populate until Schedule 7b wires a real
provider, but the worker is ready for it).

## Next action

Part 4C (public rendering and abuse boundary — share/embed, published-version reads, Turnstile, bounded
uploads, validation, rate limits) is next; dependency (4B) is fully closed. Scope it with Jafar before
building: read the 4C roadmap entry, confirm what's still assumed vs. decided, then propose the plan.

## Env notes

- Dev server can crash blank after a restart with "Cannot read properties of undefined (reading 'call')" —
  a mixed `?v=` dep-cache issue. Fix: `rm -rf node_modules/.vite` + hard reload (Ctrl+Shift+R).
- Full `npm run check` OOMs — verify TS with a scratch tsconfig (`extends: "./tsconfig.json"`, includes
  `.svelte-kit/ambient.d.ts` + `.svelte-kit/env.d.ts` + `.svelte-kit/non-ambient.d.ts` + `src/app.d.ts` +
  each touched file's own `.svelte-kit/types/.../$types.d.ts`) — delete it when done, it's scratch-only.
  Prettier can't glob `(app)` — pass full paths.
- Two deliberate departures from Jobber (radius instead of drawn service area; fixed buffer instead of
  real drive-time) are noted in `docs/PRODUCT.md` § 9 and `.claude/skills/jobber/jobber-02-requests-leads.md` § 5.
- pgTAP tests run against the shared dev database, not an isolated instance — real orgs carry real data.

Resume command: `continue contractor settings`.
