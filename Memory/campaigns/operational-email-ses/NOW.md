# Operational Email on SES: Current Checkpoint

Goal: contractor email runs only on Amazon SES; Brevo stays only for platform/Jafar email (`src/lib/server/email/brevo.ts`).

## State

Parts 1–4b done (4b D live-proven 2026-09-26 on Raad). Active: Part 6 step 4 (ROADMAP row 6).

## Exact next action

Remove sender is live (migration applied + browser-proven on Raad 2026-09-26 with a throwaway sender).
Step 5 (needs Jafar's explicit yes first): Jafar panel Remove + Set up on Raad's everyday email, recreate
sender office@mail.<root> "Raad LTD Office" (assigned to owner, default, manual on, automated per new
default), live send + Gmail reply.
After Part 6: Part 5, then Part 7. Open: delete unused Brevo domain notifications.upliftcontractor.com? (ask)

## Blockers

Step 4 needs Jafar's explicit yes (irreversible provider deletes). AWS: `aws --profile ucrm` (renew `aws sso
login --sso-session ucrm`). Check lives on the Jafar panel org page → Communications tab.

Resume: `continue operational email ses`.
