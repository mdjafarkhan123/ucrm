# Communications Activation: Current Checkpoint

## Goal
Make Communications deliver email, SMS, then marketing through a GHL-style unified inbox. Email is live;
SMS Stages 1/2A/2B/2C and contractor Stages 3A/3B/3C are all complete.

## Active part
Stage 3C is DONE and committed (48ccd7c). Next dependency-ready part is **3D SMS usage** (balance, top-up
requests, lean health and ledger using existing Stage 2C money truth).

## What just finished (3C-3, committed 48ccd7c)
Added Phone numbers, Compliance & sender info, and Holds/opt-outs sections to
`src/routes/(app)/settings/communications/sms/+page.svelte`, backed by the 3C-2 endpoints, plus new client lib
`src/lib/communications/sms-settings.ts` (types + fetchers, mirrors `sms-registration.ts`). Numbers: list,
inline rename, make-default (disabled unless ready + SMS-capable); release/replacement have no backend yet, so
they show as a "contact Jafar" notice, not a fake button. Compliance: two toggles + custom wording + 1–60 day
interval with explicit Save. Holds: opt-out count + active holds list, read-only. Verified: svelte-check
0/3421, Prettier clean, 20/20 relevant vitest green, browser-verified live on dev (rename + compliance save
round-tripped with toasts, no console errors). Committed SMS-only (12 files: 3C-1 migration + pgTAP, 3C-2's 6
API files, 3C-3's page + client lib, the product blueprint doc) — `database.types.ts` deliberately left out,
matching how 3A/3B shipped; it still lags several other in-flight campaigns' schema changes on this branch and
needs its own regeneration pass, not a partial one.

## Exact next action
Start 3D SMS usage: data → API → UI split like 2C/3C, reusing Stage 2C's money/ledger tables.

## Uncommitted / unapplied
Nothing for this campaign. (Other campaigns still have their own uncommitted work on this branch, including
`database.types.ts` — not this campaign's to resolve.)

## Constraint
A2P 10DLC cannot be completed for Jafar's test org; nothing actually sends yet. Provider-owned actions (buy/
release a number, carrier submission) stay Jafar's, never direct contractor mutations.

## Essential pointers
- Product UI: `docs/communications-sms-product-ui-blueprint.md` section 4 (SMS usage) for 3D.
- API template: `src/routes/api/settings/communications/sms/registrations/+server.ts` and the 3C-2 routes.

Resume: `read memory and continue — communications-activation`.
