# Operational Email on SES: Current Checkpoint

Goal: contractor email (setup, sending, events, replies) runs only on Amazon SES; zero Brevo on the contractor
side. Brevo stays only for platform/Jafar emails (`src/lib/server/email/brevo.ts`, untouched).

## State

Part 6 approved 2026-09-25. All work is on `main` in the main folder (email worktree merged
at `17515c7` and removed).
Steps 1–3 done and committed (3 = migration `20260925180000_operational_email_ses_only_tables.sql`, pushed live;
Raad's Brevo-era test emails deleted with Jafar's OK). pgTAP fixtures updated but not run (no local stack).

## Exact next action

Step 4 done 2026-09-25: Brevo now holds only sender 1, `contact.`/`notifications.upliftcontractor.com`, and no
inbound webhooks (all contractor-era leftovers deleted with Jafar's OK). Next: step 5 live test.

## Blockers

Live test (step 5) needs `cloudflared tunnel run` and Jafar sending replies. Raad currently has no receiving
row; step 5's fresh Set up creates it. AWS: `aws --profile ucrm` (`aws sso login --sso-session ucrm`).
Known gap: org purge leaves Marketing CloudFront click-domain resources (marketing campaign's concern).

Resume: `continue operational email ses`.
