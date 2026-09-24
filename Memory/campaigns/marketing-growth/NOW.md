# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

M1-M5 complete. M6a, M6b, M6c closed (M6c load test passed 2026-09-24 -- results in ROADMAP.md's M6 row).

## Exact next action

M6f earned warm-up (`docs/marketing-first-release-plan.md` §3 M6f). Database, wording, readiness API and the
Overview card (`MarketingWarmupCard.svelte`, render-tested) are built and committed.
Next: browser-check the card on Raad LTD's Marketing Overview (desktop + narrow width). The Chrome extension was
not connected on 2026-09-24. Raad LTD has real warm-up data (step 1, 100/day); if Marketing will not open for
it, the check needs a Jafar-approved temporary Marketing override. Then close M6f in ROADMAP.
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
