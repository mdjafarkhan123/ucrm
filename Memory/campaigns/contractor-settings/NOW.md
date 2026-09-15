# Contractor Settings: Current Checkpoint

## Goal

Give contractors one permission-aware control room for business identity and feature-owned settings.

## Where things stand

Part 4 closed 2026-09-12. Part 5A (Invoice & payment settings) closed 2026-09-13 — full browser pass on Raad
LTD done as both owner and a non-owner test role, all 5 checks correct (see ROADMAP.md for detail). That pass
found and fixed one real bug: `createInvoicePaymentTerm` (`src/lib/settings/api.ts`) posted to
`/api/settings/invoices/terms`, a URL with no route — the real create route is `POST /api/settings/invoices`.
Every "Add term" was silently 404ing before the fix.

## Next action

Paused by Jafar 2026-09-13. He picked "Job fields & forms", but on inspection the only unbuilt piece is Job
**custom fields** (checklists already ship end to end; job forms == checklists in Jobber). Custom fields is a
real but "later / power-user" feature (proven cross-cutting pattern; approved shape = one extensible engine
wired to Jobs only). Jafar has no launch pull toward it, so it is shelved as later, not built. No code written.

Two open housekeeping items when Settings resumes:

1. **Part 5A invoice files are still UNCOMMITTED** (untracked in git — `InvoiceDefaultsDialog.svelte`,
   `InvoicePaymentTermDialog.svelte`, `settings/invoices/*`, `api/settings/invoices/*`, the two migrations,
   the pgTAP test). Closed in Memory, not yet in Git. Commit before this work is lost.
2. Remaining Settings work is all gated on other campaigns/features (rest of Part 5 needs its owning feature;
   6F-2..6I need owning domains + approval; 6D-6/6E-2 need the VPS) or is one small Quotes-owned Part-1
   frozen-branding check. Nothing here is dependency-ready to build alone right now.

Focus moved to the crm-launch-readiness campaign this session (gap-list walkthrough).

## Blockers

Nothing broken. Every remaining Settings item waits on another feature, the VPS decision, or Quotes.

## Env notes

- 4 pre-existing svelte-check errors unrelated to this work (see Part 4 history in ROADMAP.md).
- Dev server can crash blank after restart — `rm -rf node_modules/.vite` + hard reload.
- `npm run check` can OOM in this shell; use
  `NODE_OPTIONS="--max-old-space-size=8192" npx svelte-check --tsconfig ./tsconfig.json` instead.
- Dev server already running this session on `localhost:5173` — no Cloudflare tunnel needed for Chrome on
  this machine, just navigate straight to localhost.

Resume command: `continue contractor settings`.
