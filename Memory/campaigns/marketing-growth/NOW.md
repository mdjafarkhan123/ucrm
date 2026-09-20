# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

In progress 2026-09-20. M1 and M2 complete and committed (`8ef77f7`, `a3f13ca`, `e854a84`).

M3a (data layer + API routes) is done, verified, and about to be committed. `npm run db:types` was stale
(migration was applied but types were never regenerated) and caused 52 false compile errors; regenerated and
fixed two small real bugs surfaced along the way: `preview_text` was inferred as a required key instead of
optional in `campaign-content.ts` (fixed with a trailing `.optional()`), and `marketing_update_campaign_draft`'s
generated RPC arg types say `string` instead of `string | null` for its two nullable uuid params (Postgres
codegen quirk, worked around with a narrowing cast in `campaigns.ts`). Also closed a real tenant-isolation gap:
`createCampaign` accepted a `customer_group_id`/`template_id` straight from the client with no ownership check
(the update RPC already had one) -- added the same check before insert.

`npm run check` now passes 0 errors, `render-email.spec.ts`'s 7 tests pass, Prettier is clean on every new/edited
file. New API routes (mirroring Customer Groups' permission/Zod/error convention exactly):
`src/routes/api/marketing/campaigns/+server.ts` (GET list, POST create), `.../campaigns/[id=uuid]/+server.ts`
(GET, PATCH, DELETE), `.../campaigns/preview/+server.ts` (POST content → rendered HTML, no id), and
`src/routes/api/marketing/templates/+server.ts` (GET list platform+org templates, POST copy). New
`src/lib/server/marketing/business-identity.ts` supplies the render footer's business name/address. Client
wrappers added to `src/lib/marketing/api.ts` (fetchCampaigns, fetchCampaign, create/update/delete, preview,
fetchMarketingTemplates, copy). No browser verification yet -- there is no UI to click through until M3b.

## Active part

M3a is done pending the commit. M3b (the five-step journey UI, block editor, Templates screen) has not started.

## Exact next action

Commit M3a (all the files above, already staged), then start M3b: the five-step campaign journey UI, the
drag block editor, and the Templates nav screen. Browser-verify M3b end to end like M2b was.

## Blockers

None. M4 needs SES production access + real SES send code (unrelated, later, also owns the deferred test-email
piece -- see plan doc). M9 blocked until Communications A2 passes live SMS gates (unrelated, later).

## Pointers

Plan: `docs/marketing-first-release-plan.md` (§3 M3, M4). Blueprint: `docs/marketing-product-blueprint.md` (§8
step 3 for block editor spec, §5 for the Templates nav view). M2's customer-groups UI files are the convention
template for M3b's screens.

Resume: `continue marketing growth` — go straight to "Exact next action" above.
