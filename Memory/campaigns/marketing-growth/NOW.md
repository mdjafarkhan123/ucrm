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
Next: (1) Jafar runs `! node scripts/cloudflare-add-cname.mjs upliftcontractor.com click.news.test.upliftcontractor.com
d30azkeso6lzew.cloudfront.net --apply` (auto mode blocks DNS writes by Claude). (2) `aws cloudfront
create-distribution-tenant --distribution-id E3BC29BRFLB91P --name ucrm-org-18f0d717-904e-48d8-bd99-9df7e3844cda
--connection-group-id cg_3Jl58Y3IZa93OHuOotP7eXXB7K0 --domains Domain=click.news.test.upliftcontractor.com
--managed-certificate-request ValidationTokenHost=cloudfront --enabled` (fails until the CNAME exists). (3) Wait for
cert; `curl --head https://click.news.test.upliftcontractor.com/favicon.ico` must show `x-amz-ses-request-protocol:
https` (risk: Host forwarding + HTTPS origin may fail awstrack's cert check). (4) Tracking options on config set
`ucrm-marketing-18f0d717-904e-48d8-bd99-9df7e3844cda`, 1 simulator send + click reaches Results. (5) Tighten IAM,
then build plan for Jafar. Later: M6e (blocked on `operational-email-ses`), check 15 review.

## Open findings (raise with Jafar)

- Marketing wake cron jobs fail every minute (Vault target URLs unset) -- production-cutover work.
- 2 harmless leftover messages in `ucrm-ses-events-dlq`; Jafar to clear via AWS console.
- `npx supabase test db` has many pre-existing "Bad plan" failures outside marketing's scope.
- Raad LTD has no Marketing allowance (override ended 2026-09-24); live checks need a new approved override.
- Blueprint §12 Results Q4 (cross-campaign "strongest") left for the list page's insight cards, not built.
- Old test campaign `cce6af97-...` fails to open (ErrorState); undiagnosed, low priority.

## Pointers

Plan §3; blueprint §12-13, §19. Resume: `continue marketing growth`.
