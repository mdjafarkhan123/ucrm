# Operational Email on SES Roadmap

Approved behavior: `docs/contractor-email-contract.md` (incl. 2026-09-23 cutover amendment). Architecture:
`docs/research/amazon-ses-contractor-email-inbound-architecture-2026-09-19.md`.

## Goal

Move contractor operational email (domain setup, sending, delivery events, customer replies) from Brevo to
Amazon SES with an easy owner/contractor workflow. Allowances, warm-up, reputation, suppressions and senders
already exist provider-neutrally; this is a provider swap plus the setup UI, not a rebuild.

## Start rule

No coding until the marketing-growth agent has committed its current SES work (`dns-reconcile.ts`, the
marketing-domain route, `CommunicationsWorkspace.svelte`, `email-domain-activation.ts` edits). Then build in a
separate git worktree on its own branch (started 2026-09-24: `../Ucrm-email-ses`, branch `operational-email-ses`); merge the shared `ses.ts`/`ses-env.ts` overlap at the end.

| Part | Outcome | State | Depends on | Completion gate |
| --- | --- | --- | --- | --- |
| 1 | Research check + screen designs | Done 2026-09-24 (`e786e40`; designs in contract "Email setup screens") | Start rule | Jobber/GHL setup screens reviewed; Jafar approves designs for the owner Email card and contractor Settings → Email request flow |
| 2a | Operational domain setup on SES (backend) | Built `174a8ec` (worktree); live Raad run pending | 1 | Owner Set up creates mail + reply SES identities, bounce.mail MAIL FROM, `ucrm-operational-<org>` config set in the org tenant via Cloudflare; Check/Remove handle SES rows; reply MX + receiving row deliberately untouched until Part 4; Raad re-activated and verified live |
| 2b | Owner Email card UI | Planned | 2a | Approved "Email setup screens" owner card (one Email card, Everyday + Marketing rows, one status + one action each) replaces EmailDomainActions/MarketingDomainActions; browser-verified |
| 3 | Outbound sending + delivery events on SES | Planned | 2a | Email worker sends via SES with config set and opaque Reply-To; delivery/bounce/complaint update projection and suppressions; live send proven |
| 4 | Customer replies on SES | Planned | 3; Jafar approval before creating AWS resources | One owned us-east-1 receipt-rule set → private S3 (30-day expiry) → SNS → SQS+DLQ → worker; reply, duplicate, oversized attachment, expired alias, auto-response, recovery proven live; a reply to a Marketing campaign email lands in the right Conversation with Campaign origin (marketing M5 recheck) |
| 5 | Contractor request-setup flow | Planned | 2b | Request email setup in Settings → Email, Needs attention item for Jafar, send-refusal links there (absorbs old P3 deferral) ; browser-verified |
| 6 | Cutover, cleanup, live-mailbox rehearsal | Planned | 3–5 | Raad fully on SES; stale ap-northeast-1 MX on `test.upliftcontractor.com` removed; Brevo contractor code/webhooks/cleanup paths removed (platform Brevo kept); rehearsal on `upliftcontractor.com` with Hostinger mail working before and after; marketing M6e passes: re-run the M6c representative marketing burst with operational email also on SES and show no material operational-email delay (method and baseline in git `716250a` marketing ROADMAP M6c row; Jafar pre-approved reopening Raad LTD Marketing allowance/warm-up overrides for the test) |
| 7 | Over-allowance email credit | Planned (approved 2026-09-24, contract `108b445`) | None in this campaign; reuses SMS Communication Balance | Essential email never stops on allowance/balance; optional overage charges Communication Balance and pauses when empty; Jafar price setting shows SES cost + industry hints; browser-verified |

## Known constraints

- Part 3 must add the event destination to `ucrm-operational-<org>` (not done in 2a) and route operational
  events apart from Marketing ones on the shared SNS topic. Part 6 must delete the orphaned Brevo domain for
  any org moved to SES (2a overwrites `provider_domain_id` with the SES ARN).

- Rehearsal on Jafar's real domain: export the Cloudflare zone first, test outside business hours, check the
  Hostinger inbox sends/receives before and after. `bounce.mail.upliftcontractor.com` already has SES MAIL FROM
  records, so choose unoccupied prefixes for the rehearsal.
