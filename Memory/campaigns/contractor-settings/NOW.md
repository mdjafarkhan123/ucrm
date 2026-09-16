# Contractor Settings: Current Checkpoint

## Goal

Give contractors one permission-aware control room for business identity and feature-owned settings.

## Where things stand

Every part with a dependency-ready path is closed, most recently Part 1's last item (Quote branding freeze +
a real revise-quote bug fix, committed `339516b` 2026-09-17). See ROADMAP.md for full history.

## Next action

Nothing is dependency-ready right now. Every remaining item waits on another feature, an owning domain's
approval, or the VPS decision (rest of Part 5; 6F-2..6I; 6D-6/6E-2). Job **custom fields** remain deliberately
shelved as "later" per Jafar's 2026-09-13 call — not built, no code written.

This campaign stays open only because those dependencies may clear later. Nothing to do here until Jafar
names a specific unblocked item or a dependency (a new feature, the VPS, an approval) actually lands.

## Blockers

Nothing broken. Every remaining Settings item waits on another feature, the VPS decision, or an owning
domain's approval.

## Env notes

- 4 pre-existing svelte-check errors unrelated to this work (see Part 4 history in ROADMAP.md).
- Dev server can crash blank after restart — `rm -rf node_modules/.vite` + hard reload.
- `npm run check` can OOM in this shell; use
  `NODE_OPTIONS="--max-old-space-size=8192" npx svelte-check --tsconfig ./tsconfig.json` instead.

Resume command: `continue contractor settings` — but check first whether a real dependency has actually
cleared, since nothing here is currently buildable on its own.
