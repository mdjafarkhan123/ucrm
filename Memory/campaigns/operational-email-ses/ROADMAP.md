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
separate git worktree on its own branch; merge the shared `ses.ts`/`ses-env.ts` overlap at the end.

| Part | Outcome | State | Depends on | Completion gate |
| --- | --- | --- | --- | --- |
| 1 | Research check + screen designs | Planned | Start rule | Jobber/GHL setup screens reviewed; Jafar approves designs for the owner Email card and contractor Settings → Email request flow |
| 2 | Operational domain setup on SES | Planned | 1 | Owner "Set up" creates sending + receiving SES identities (+ MAIL FROM, config set in the org's existing tenant) via Cloudflare; Raad re-activated and verified live |
| 3 | Outbound sending + delivery events on SES | Planned | 2 | Email worker sends via SES with config set and opaque Reply-To; delivery/bounce/complaint update projection and suppressions; live send proven |
| 4 | Customer replies on SES | Planned | 3; Jafar approval before creating AWS resources | One owned us-east-1 receipt-rule set → private S3 (30-day expiry) → SNS → SQS+DLQ → worker; reply, duplicate, oversized attachment, expired alias, auto-response, recovery proven live |
| 5 | Contractor request-setup flow | Planned | 2 | Request email setup in Settings → Email, Needs attention item for Jafar, send-refusal links there (absorbs old P3 deferral) ; browser-verified |
| 6 | Cutover, cleanup, live-mailbox rehearsal | Planned | 3–5 | Raad fully on SES; stale ap-northeast-1 MX on `test.upliftcontractor.com` removed; Brevo contractor code/webhooks/cleanup paths removed (platform Brevo kept); rehearsal on `upliftcontractor.com` with Hostinger mail working before and after |

## Known constraints

- Rehearsal on Jafar's real domain: export the Cloudflare zone first, test outside business hours, check the
  Hostinger inbox sends/receives before and after. `bounce.mail.upliftcontractor.com` already has SES MAIL FROM
  records, so choose unoccupied prefixes for the rehearsal.
