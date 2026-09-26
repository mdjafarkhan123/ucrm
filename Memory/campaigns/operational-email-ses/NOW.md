# Operational Email on SES: Current Checkpoint

Goal: contractor email runs only on Amazon SES; Brevo stays only for platform/Jafar email (`src/lib/server/email/brevo.ts`).

## State

Parts 1–4b done (4b D live-proven 2026-09-26 on Raad). Active: Part 6 step 4 (ROADMAP row 6).

## Exact next action

Step 5 in progress on Raad (Jafar approved 2026-09-26). Done: office@ sender removed; Everyday email removed
(fix `8aa2d33`) and re-set up; mail.test + reply.test verified -> Everyday email "Ready" (2026-09-26).
Concurrent-session worry cleared by Jafar. Next (needs Raad owner/admin signed in; Chrome is signed in as
Jafar = field member there; Claude may not type live passwords -> ask Jafar to sign in):
1. /settings/communications/email: recreate sender office@mail.test.upliftcontractor.com "Raad LTD Office",
   assigned Jafar Khan, default, manual on, automated on. 2. Live send + Gmail reply into the inbox.
After Part 6: Part 5, then Part 7. Open: delete unused Brevo domain notifications.upliftcontractor.com? (ask)

## Blockers

Step 4 needs Jafar's explicit yes (irreversible provider deletes). AWS: `aws --profile ucrm` (renew `aws sso
login --sso-session ucrm`). Check lives on the Jafar panel org page → Communications tab.

Resume: `continue operational email ses`.
