# Operational Email on SES: Current Checkpoint

Goal: contractor email runs only on Amazon SES; Brevo stays only for platform/Jafar email (`src/lib/server/email/brevo.ts`).

## State

Parts 1–4b done (4b D live-proven 2026-09-26 on Raad). Active: Part 6 step 4 (ROADMAP row 6).

## Exact next action

Step 5 in progress on Raad (Jafar approved 2026-09-26). Done: office@ sender removed; Everyday email removed
(needed fix `8aa2d33`: unlink SES tenant resources before delete) and re-set up; mail.test verified.
PAUSED: another session (Jafar-panel login) set up + removed Raad's Everyday email at 04:38/04:41 UTC
mid-step. Confirm with Jafar that nothing else is touching Raad's email, then:
1. Jafar panel Check until reply.test shows verified (SES already SUCCESS) -> Everyday email "Ready".
2. Recreate sender office@mail.test.upliftcontractor.com "Raad LTD Office", assigned Jafar Khan, default,
   manual on, automated on. 3. Live send + Gmail reply into the inbox.
After Part 6: Part 5, then Part 7. Open: delete unused Brevo domain notifications.upliftcontractor.com? (ask)

## Blockers

Step 4 needs Jafar's explicit yes (irreversible provider deletes). AWS: `aws --profile ucrm` (renew `aws sso
login --sso-session ucrm`). Check lives on the Jafar panel org page → Communications tab.

Resume: `continue operational email ses`.
