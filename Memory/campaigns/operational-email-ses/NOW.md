# Operational Email on SES: Current Checkpoint

Goal: contractor email runs only on Amazon SES; Brevo stays only for platform/Jafar email (`src/lib/server/email/brevo.ts`).

## State

Parts 1–4b done. Part 6 done 2026-09-26 (step 5 live on Raad: fresh Set up, office@ sender, delivered send,
Gmail reply accepted into the Inbox under Greenfield Property Group).

## Exact next action

Jafar 2026-09-26: "on new session do all the necessary improvements you noticed and do the rest work".
1. Fix (approved): sender dialog "Assigned team member" list shows 4 "Unnamed team member" rows (role test
   users without names) -- show a real fallback (e.g. email) so members are distinguishable; email preview
   (client "Message" dialog) shows "From: Your eligible email identity" -- show the actual sender address.
2. Irreversible deletes still need a plain yes (ask once at start): delete unused Brevo domain
   notifications.upliftcontractor.com (keep contact. -- SYSTEM_FROM_EMAIL); purge the 3 stale 2026-09-25
   "SES live test 2" reply copies in `ucrm-ses-inbound-dlq` (already filed).
3. ROADMAP row 6 follow-ups: Marketing M6e burst check; Email card Check ~10 s; failed Check (409
   `subdomain_occupied`) shows no error on the Jafar Email card.
4. Then Part 5 (contractor request-setup flow; ROADMAP row 5) -- product decisions, use grilling. Part 7 after.

## Blockers

AWS: `aws --profile ucrm` (renew `aws sso login --sso-session ucrm`).

Resume: `continue operational email ses`.
