# Operational Email on SES: Current Checkpoint

Goal: contractor email runs only on Amazon SES; Brevo stays only for platform/Jafar email (`src/lib/server/email/brevo.ts`).

## State

Parts 1–4b done (4b D live-proven 2026-09-26 on Raad). Active: Part 6 step 4 (ROADMAP row 6).

## Exact next action

Part 6 step 4 done 2026-09-26 (Jafar deleted the last Brevo transactional webhook; no contractor Brevo left).
Step 5 is blocked by a product gap: Jafar-panel Remove refuses while live senders exist
(`begin_communication_email_domain_removal`), but no UI or API removes a sender (`senders/[senderId]` has
PATCH only; "active" off still counts). Awaiting Jafar's choice: build contractor "Remove sender" first
(recommended), or accept the 2026-09-26 live proof and skip the fresh Set up. Raad's sender to recreate after:
office@mail.<root>, "Raad LTD Office", assigned to owner, business default, manual only.
Open question for Jafar: delete unused platform Brevo domain notifications.upliftcontractor.com?
After Part 6: Part 5, then Part 7.

## Blockers

Step 4 needs Jafar's explicit yes (irreversible provider deletes). AWS: `aws --profile ucrm` (renew `aws sso
login --sso-session ucrm`). Check lives on the Jafar panel org page → Communications tab.

Resume: `continue operational email ses`.
