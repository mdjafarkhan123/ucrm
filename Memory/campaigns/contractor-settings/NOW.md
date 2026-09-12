# Contractor Settings: Current Checkpoint

## Goal

Give contractors one permission-aware control room for business identity and feature-owned settings.

## Where things stand

Part 4B-1 (request-form builder) is closed 2026-09-12 — see ROADMAP.md for what shipped. Live-verified end to
end on Raad LTD this session; no known bugs.

## Next action

No dependency-ready part remains in Part 4 right now: 4B-2 (booking rules) needs Scheduling, and 4C/4D/4E need
the rest of Part 4B. Ask Jafar what to pick up next — options are starting Scheduling (unblocks 4B-2), Part 5
(feature-owned settings, currently unscoped), or a different campaign entirely.

## Env notes

- Dev server can crash blank after a restart with "Cannot read properties of undefined (reading 'call')" —
  a mixed `?v=` dep-cache issue. Fix: `rm -rf node_modules/.vite` + hard reload (Ctrl+Shift+R).
- Full `npm run check` OOMs — verify TS with a scratch tsconfig that `extends: "./tsconfig.json"` (not
  `.svelte-kit/tsconfig.json` directly — that config alone is missing `moduleResolution: bundler` etc. needed
  for `?raw` imports and `$app/*`) and explicitly includes `.svelte-kit/ambient.d.ts` + `env.d.ts` +
  `non-ambient.d.ts` alongside the target files — a custom `include` array replaces the parent's, it does not
  merge. Prettier can't glob `(app)` — pass full paths.
- Raad LTD owner login has `settings.forms.manage` (owner/admin only); office/sales/finance roles do not.
- Test form in Raad LTD: id `abcb9f54-04de-4e95-8eb6-66ee4d378d29` ("Kitchen Remodel Request"), still a Draft
  with a saved section + question from this session's verification pass.

Resume command: `continue contractor settings`.
