# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

M1-M5 complete. M6a, M6b, M6c, M6d, M6f closed (M6d branded click links live-verified 2026-09-24).

## Exact next action

Nothing dependency-ready to build. Remaining: M6e (blocked on `operational-email-ses` -- re-run the shared-SES-rate
load check after operational email moves to SES), then blueprint §19 check 15 review with Jafar. Ask Jafar which to
pick up, or pause.

## Open findings (raise with Jafar)

- Marketing wake cron jobs fail every minute (Vault target URLs unset) -- production-cutover work.
- Production AWS account needs the one-time branded-links setup (research doc's last section) at cutover.
- 2 harmless leftover messages in `ucrm-ses-events-dlq`; Jafar to clear via AWS console.
- `npx supabase test db` has many pre-existing "Bad plan" failures outside marketing's scope.
- `svelte-check` has 3 pre-existing "union type too complex" errors (pipeline drawer, app layout, new invoice).
- Jafar gave standing approval (2026-09-24) to reopen Raad LTD's Marketing allowance override whenever a test needs it.
- Blueprint §12 Results Q4 (cross-campaign "strongest") left for the list page's insight cards, not built.
- Old test campaign `cce6af97-...` fails to open (ErrorState); undiagnosed, low priority.

## Pointers

Plan §3; blueprint §12-13, §19. Resume: `continue marketing growth`.
