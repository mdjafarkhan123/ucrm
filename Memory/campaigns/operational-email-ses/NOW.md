# Operational Email on SES: Current Checkpoint

Goal: contractor email runs only on Amazon SES; Brevo stays only for platform/Jafar email (`src/lib/server/email/brevo.ts`).

## State

Parts 1–4b done. Part 6 done 2026-09-26 (step 5 live on Raad: fresh Set up, office@ sender, delivered send,
Gmail reply accepted into the Inbox under Greenfield Property Group).

## Exact next action

1. Ask Jafar two yes/no questions, then act: (a) delete unused Brevo domain notifications.upliftcontractor.com
   (keep contact. — SYSTEM_FROM_EMAIL uses it); (b) purge the 2 stale 2026-09-25 messages in
   `ucrm-ses-inbound-dlq` (replies to "SES live test 2", already re-filed).
2. Then start Part 5 (contractor request-setup flow; ROADMAP row 5) — product decisions, use grilling.
Small UI notes seen in step 5 (not fixed): sender "Assigned team member" list shows 4 "Unnamed team member"
rows (role test users without names); email preview shows "From: Your eligible email identity" not the address.
Still owed from ROADMAP row 6: Marketing M6e burst check. Part 7 after Part 5.

## Blockers

AWS: `aws --profile ucrm` (renew `aws sso login --sso-session ucrm`).

Resume: `continue operational email ses`.
