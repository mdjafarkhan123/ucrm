# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

M3 complete 2026-09-20. All five journey steps (Goal, Customers, Email, Delivery, Review) are built, saved,
and browser-verified end to end against Raad LTD (`e53d53a`, `cf61575`, `5576295`, `eedc056`, `fe7cba9`).
Review shows the rendered desktop/mobile message, goal and customer-group rules, exact eligible/excluded
counts with reasons (reusing `CustomerGroupPreview`), sender/replies, CTA destination, the allowance notice,
the "cannot be recalled" statement, and an owner/admin-gated Send/Schedule button that stays disabled --
nothing sends via SES yet.

## Not yet done

M4 (real SES send code, launch command, gradual dispatcher, cancellation, "send a test email") is the only
part left before a campaign can actually go out.

## Exact next action

M4 needs SES production access first (the account is still in sandbox) -- that's Jafar's action, not a build
step. Ask Jafar whether SES production access has been requested/granted before starting M4. If not yet
requested, that's the blocker to raise with him.

## Blockers

M4 blocked on SES production access (infrastructure/provider action, outside this session's authorization).
M9 (SMS marketing) blocked until Communications A2 passes live SMS gates -- later.

## Pointers

Plan: `docs/marketing-first-release-plan.md` (§2 provider boundary, §3 M4). Blueprint:
`docs/marketing-product-blueprint.md` (§8, §9). Roadmap: `Memory/campaigns/marketing-growth/ROADMAP.md` M4 row.

Resume: `continue marketing growth` -- ask Jafar about SES production access before starting M4.
