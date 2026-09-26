# Operational Email on SES: Current Checkpoint

Goal: contractor email runs only on Amazon SES; Brevo stays only for platform/Jafar email (`src/lib/server/email/brevo.ts`).

## State

Parts 1–4b and 6 done. 2026-09-26 cleanup session (`462fdb4`): previews show the real From address, team
lists show unnamed members by email and drop removed people, Email card errors show inside dialogs, Check
runs provider calls in parallel. Brevo `notifications.` domain deleted; stale DLQ reply deleted.

## Exact next action

Check speed done 2026-09-26 (`0cb2f3a`): measured live on Raad 6-8 s -> 3.6-4.9 s (server side, no browser).

1. Part 6 follow-up: Marketing M6e burst check (ROADMAP row 6; M6c method/baseline in git `716250a`
   marketing ROADMAP M6c row). Deleting its test data afterwards needs Jafar's yes.
2. Then Part 5 (contractor request-setup flow; ROADMAP row 5) -- product decisions with Jafar, use grilling.
   Part 7 after.

## Open asks for Jafar

- `ucrm-ses-inbound-dlq` still holds one AWS "setup notification" test ping (2026-09-25, recipient@example.com).
  Harmless junk; delete only with Jafar's yes.
- Cloudflare DNS records for the deleted Brevo `notifications.upliftcontractor.com` may remain; harmless.

## Blockers

AWS: `aws --profile ucrm` (renew `aws sso login --sso-session ucrm`).

Resume: `continue operational email ses`.
