# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

In progress 2026-09-20. M1, M2, M3a, Templates tab, journey Steps 1-3, and now Step 4 (Delivery) are committed
(`e53d53a`, `cf61575`, `5576295`, `eedc056`). Step 4 shows the org's eligible sender/reply routing (read-only --
no picker, since nothing sends yet to freeze a choice against), the customer group's live recipient count, the
Marketing allowance, and a call-to-action picker (existing published form / website / phone), each disabled
with a reason when its destination isn't on file. A form CTA chosen in an earlier draft is flagged if it's
since been unpublished or archived. Browser-verified end to end against Raad LTD: real sender/forms/allowance
data rendered, the "choose a CTA" gate, the internal-form picker's live "Open form" link, and save + hard
reload correctly restoring the saved CTA. Test campaign/customer group were deleted afterward through the real
app endpoints (not raw SQL).

## Not yet done

Journey Step 5 (Review, blueprint `docs/marketing-product-blueprint.md` §8) is not built -- `CampaignComingSoonStep`
still renders for it. Send/Schedule itself stays disabled until M4 (needs SES production access).

## Exact next action

Design then build journey Step 5 (Review): rendered desktop/mobile message, sender/reply, goal and customer-group
rules, exact eligible count, excluded count with reasons, CTA destination, allowance/reputation notices, the
"sent email cannot be recalled" statement, and a disabled Send/Schedule (owner/admin-only) with an explanatory
note -- same M3/M4 split as Delivery. "Send a test email" stays out of scope (moved to M4 per M3's own note --
no SES send path exists yet). Read blueprint §8 Step 5 before starting. Browser-verify end to end before
committing, same pattern as Steps 1-4.

## Blockers

None for Step 5 UI. M4 (actual Send/Schedule, test email) needs SES production access + real SES send code --
later. M9 blocked until Communications A2 passes live SMS gates -- later.

## Pointers

Plan: `docs/marketing-first-release-plan.md` (§3 M3, M4). Blueprint: `docs/marketing-product-blueprint.md` (§8
step 5). Roadmap: `Memory/campaigns/marketing-growth/ROADMAP.md` M3 row.

Resume: `continue marketing growth` -- go straight to "Exact next action" above.
