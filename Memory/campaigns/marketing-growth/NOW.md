# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

In progress 2026-09-20. M1, M2, M3a, Templates tab, and journey Steps 1-2 are committed (`e53d53a`, `cf61575`).
This session browser-verified Step 3 (the block editor: subject/preview, all 6 block types add/reorder/remove,
variable insertion, real MJML preview, save with the client-side field-error check, persistence after reload)
against Raad LTD end to end, then committed it: `5576295`. All test campaigns/customer group created during
verification were deleted afterward through the real app endpoints (not raw SQL).

## Not yet done

Journey Steps 4-5 (Delivery and Review UI per blueprint `docs/marketing-product-blueprint.md` §8) are not built
-- `CampaignComingSoonStep` still renders for them. Send/Schedule itself stays disabled until M4 (needs SES
production access), but the Delivery step's sender/reply/CTA-destination fields and the Review step's read-only
summary are in scope now, ending in a disabled Send/Schedule button with an explanatory note.

## Exact next action

Design then build journey Step 4 (Delivery): sender/reply destination display, CTA link/booking-form/phone
picker, "internal destination still exists" check. Read blueprint §8 Step 4 (quoted in prior session context)
before starting -- follow Non-Negotiable Rule 3 (research how Jobber does campaign delivery config) if any
choice is unresolved. Browser-verify end to end before committing, same pattern as Steps 1-3.

## Blockers

None for Step 4 UI. M4 (actual Send/Schedule) needs SES production access + real SES send code -- later. M9
blocked until Communications A2 passes live SMS gates -- later.

## Pointers

Plan: `docs/marketing-first-release-plan.md` (§3 M3, M4). Blueprint: `docs/marketing-product-blueprint.md` (§8
steps 4-5). Roadmap: `Memory/campaigns/marketing-growth/ROADMAP.md` M3 row.

Resume: `continue marketing growth` -- go straight to "Exact next action" above.
