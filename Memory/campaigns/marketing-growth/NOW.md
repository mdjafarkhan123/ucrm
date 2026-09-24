# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

M1-M5 complete. M6a, M6b, M6c, M6f closed (M6f card browser-verified 2026-09-24).

## Exact next action

M6d branded click tracking, option A approved (CloudFront SaaS Manager, `click.news.<root>`, HttpsPolicy REQUIRE;
research `docs/research/ses-branded-click-tracking-domain-2026-09-24.md`). Jafar approved the live test on Raad LTD's
own test domain. Done 2026-09-24: multi-tenant distribution `E3BC29BRFLB91P` (origin `r.us-east-1.awstrack.me`
https-only, AllViewer, CachingDisabled), default connection group `cg_3Jl58Y3IZa93OHuOotP7eXXB7K0`, routing
endpoint `d30azkeso6lzew.cloudfront.net`. IAM inline policy `ucrm-branded-click-domain` is temporarily `cloudfront:*`
(tighten after the test). AWS CLI: `--profile ucrm-app` (credential_process `scripts/aws-credentials-from-env.sh`).
Done 2026-09-24 (live): CNAME added, tenant `dt_3JltenyORfWpxcKagdGM7XAoQpi` active with its issued cert,
HTTPS check passed, and Raad LTD's config set now tracks via `click.news.test.upliftcontractor.com` (REQUIRE).
Findings are in the research doc's "Live test findings". (4) PASSED: real Gmail send, branded click + open reached Results;
test campaign deleted (Jafar approved), allowance override ended. Next: (5) Jafar approves the build plan in
`parts/m6d-branded-links.md`, and runs `! aws sso login --profile ucrm` so Claude can apply the research doc's
"Scoped IAM policy" to user `ucrm-marketing-ses-worker` and verify. (6) Build per the packet. Later: M6e (blocked on `operational-email-ses`), check 15 review.

## Open findings (raise with Jafar)

- Marketing wake cron jobs fail every minute (Vault target URLs unset) -- production-cutover work.
- 2 harmless leftover messages in `ucrm-ses-events-dlq`; Jafar to clear via AWS console.
- `npx supabase test db` has many pre-existing "Bad plan" failures outside marketing's scope.
- Jafar gave standing approval (2026-09-24) to reopen Raad LTD's Marketing allowance override whenever a test needs it.
- Blueprint §12 Results Q4 (cross-campaign "strongest") left for the list page's insight cards, not built.
- Old test campaign `cce6af97-...` fails to open (ErrorState); undiagnosed, low priority.

## Pointers

Plan §3; blueprint §12-13, §19. Resume: `continue marketing growth`.
