# Operational Email on SES: Current Checkpoint

Goal: contractor email runs only on Amazon SES; Brevo stays only for platform/Jafar email (`src/lib/server/email/brevo.ts`).

## State

Parts 1–4b done (4b D live-proven 2026-09-26 on Raad). Active: Part 6 step 4 (ROADMAP row 6).

## Exact next action

Part 6 step 4 (checked 2026-09-26): Raad's Brevo domain, Brevo inbound webhooks and all contractor `provider='brevo'`
DB rows are already gone. Only leftover: Brevo transactional webhook id 2148798 -> deleted route
`/api/webhooks/brevo/transactional`; Jafar approved deleting it but the permission classifier blocked the API
DELETE, so Jafar deletes it in Brevo (Settings -> Webhooks) or allows it. Unused `.env` keys
`BREVO_EVENTS_WEBHOOK_SECRET`, `BREVO_TRANSACTIONAL_WEBHOOK_TOKEN`, `BREVO_INBOUND_WEBHOOK_TOKEN` can go too.
Keep Brevo domain contact. (SYSTEM_FROM_EMAIL); notifications.upliftcontractor.com is unused platform-side, ask
Jafar. Then step 5: Raad's sending row dates from the Brevo era (2026-08-29), so Remove + fresh Set up + live
send/reply with Jafar. After Part 6: Part 5, then Part 7.

## Blockers

Step 4 needs Jafar's explicit yes (irreversible provider deletes). AWS: `aws --profile ucrm` (renew `aws sso
login --sso-session ucrm`). Check lives on the Jafar panel org page → Communications tab.

Resume: `continue operational email ses`.
