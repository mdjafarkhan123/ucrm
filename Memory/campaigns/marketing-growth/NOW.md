# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

M1-M5 complete. M6a, M6b, M6c closed (M6c load test passed 2026-09-24 -- results in ROADMAP.md's M6 row).

## Exact next action

M6f earned warm-up (design approved 2026-09-24, `docs/marketing-first-release-plan.md` §3 M6f). DONE and
committed: migration `20260924130000_marketing_earned_warmup.sql` (pushed to remote), pgTAP
`marketing_earned_warmup.sql` 31/31 + dispatcher/reputation tests pass locally, `src/lib/marketing/warmup.ts`
(card wording, unit-tested), readiness API now returns `warmup`.
Next: build `MarketingWarmupCard.svelte` (SectionBlock "Sending warm-up" on Marketing Overview, under Email
readiness; render `describeMarketingWarmup(readiness.warmup)`; step ladder, today's-use bar, unlock checklist;
load design + svelte skills), then browser-check on Raad LTD (needs a Jafar-approved temporary Marketing
allowance override), then close M6f in ROADMAP.
Later: M6d branded click-tracking domain (blocks real-customer send), M6e replies (blocked on
`operational-email-ses`), check 15 doc review.

## Open findings (raise with Jafar)

- Marketing wake cron jobs fail every minute (Vault target URLs unset) -- production-cutover work.
- 2 harmless leftover messages in `ucrm-ses-events-dlq`; Jafar to clear via AWS console.
- `npx supabase test db` has many pre-existing "Bad plan" failures outside marketing's scope.
- Raad LTD has no Marketing allowance (override ended 2026-09-24); live checks need a new approved override.
- Blueprint §12 Results Q4 (cross-campaign "strongest") left for the list page's insight cards, not built.
- Old test campaign `cce6af97-...` fails to open (ErrorState); undiagnosed, low priority.

## Pointers

Plan §3 (M6f); blueprint §12-13, §19. Resume: `continue marketing growth`.
