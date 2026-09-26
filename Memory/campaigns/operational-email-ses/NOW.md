# Operational Email on SES: Current Checkpoint

Goal: contractor email runs only on Amazon SES; Brevo stays only for platform/Jafar email (`src/lib/server/email/brevo.ts`).

## State

Parts 1–4b and 6 done. 2026-09-26 cleanup session (`462fdb4`): previews show the real From address, team
lists show unnamed members by email and drop removed people, Email card errors show inside dialogs, Check
runs provider calls in parallel. Brevo `notifications.` domain deleted; stale DLQ reply deleted.

## Exact next action


1. M6e burst check DONE 2026-09-26 (dev server, Raad, real SES; 520-recipient campaign `6b1c9d14...`).
   Enqueue -> SES accepted: baseline n=11 p50 1.36 s / p95 3.30 s. During the burst n=6: p50 3.7 s, p95 15.5 s,
   max 17 s; probes that landed in a big send window (35-50 marketing sends) took 10.7-17 s, others 0.9-2.1 s.
   So a big marketing send can delay one operational email by up to ~17 s (not lost). Cause NOT isolated:
   marketing and email workers are separate endpoints, so it is SES-rate or dev-server CPU; small n. Decide with
   Jafar whether to chase it (e.g. give operational email its own reserved send capacity) or accept.
   `limit_override` on Raad reset to null. Left for Jafar's yes to delete: campaign "M6e burst test (safe to
   delete)", its 520 simulator clients/tag/group, client "M6e ops probe", the 17 probe intents.
2. Next: Part 5 (contractor request-setup flow; ROADMAP row 5) -- product decisions with Jafar, use grilling.
   Part 7 after.

## Open asks for Jafar

- `ucrm-ses-inbound-dlq` still holds one AWS "setup notification" test ping (2026-09-25, recipient@example.com).
  Harmless junk; delete only with Jafar's yes.
- Cloudflare DNS records for the deleted Brevo `notifications.upliftcontractor.com` may remain; harmless.

## Blockers

AWS: `aws --profile ucrm` (renew `aws sso login --sso-session ucrm`).

Resume: `continue operational email ses`.
