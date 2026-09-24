# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

M1-M5 complete. M6a, M6b, M6c closed (M6c load test passed 2026-09-24 -- results in ROADMAP.md's M6 row).

## Exact next action

M6f earned warm-up graduation (Jafar: build next). Read `docs/research/email-warmup-graduation-2026-09-23.md`,
propose the design to Jafar, get approval, then build. Fold in the M6 gate "a warmup-capped organization cannot
starve others": `claim_marketing_campaign_recipient` fetches only 50 candidates ordered by `launched_at` and
`continue`s past warm-up-capped rows, so one capped org with >50 waiting recipients can fill every candidate
slot and starve later-launched orgs (found by code reading 2026-09-24, not yet reproduced).
Later: M6d branded click-tracking domain (blocks real-customer send), M6e replies (blocked on
`operational-email-ses`), check 15 doc review.

## Open findings (raise with Jafar)

- Marketing wake cron jobs fail every minute (Vault target URLs unset) -- production-cutover work.
- 2 harmless leftover messages in `ucrm-ses-events-dlq`; Jafar to clear via AWS console.
- `npx supabase test db` has many pre-existing "Bad plan" failures outside marketing's scope.
- Raad LTD has no Marketing allowance now (test override ended 2026-09-24); any live Marketing check needs a
  new Jafar-approved `organization_limit_overrides` row.
- Blueprint §12 Results Q4 (cross-campaign "strongest") left for the list page's insight cards, not built.
- Old test campaign `cce6af97-...` fails to open (ErrorState); undiagnosed, low priority.

## Pointers

`docs/marketing-first-release-plan.md` §3; blueprint §12-13, §19. Resume: `continue marketing growth`.
