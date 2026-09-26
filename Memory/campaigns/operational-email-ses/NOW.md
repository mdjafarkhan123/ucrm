# Operational Email on SES: Current Checkpoint

Goal: contractor email runs only on Amazon SES; Brevo stays only for platform/Jafar email (`src/lib/server/email/brevo.ts`).

## State

Parts 1–4b done (4b D live-proven 2026-09-26 on Raad). Active: Part 6 step 4 (ROADMAP row 6).

## Exact next action

Part 6 step 4: ask Jafar's OK, then delete Raad's old Brevo sending domain and contractor inbound webhook via
the Brevo API (keep the Brevo account and `BREVO_API_KEY`). Then step 5: fresh Set up on Raad + live send and
reply with Jafar. After Part 6: Part 5 (contractor request-setup flow), then Part 7.

## Blockers

Step 4 needs Jafar's explicit yes (irreversible provider deletes). AWS: `aws --profile ucrm` (renew `aws sso
login --sso-session ucrm`). Check lives on the Jafar panel org page → Communications tab.

Resume: `continue operational email ses`.
