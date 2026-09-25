# Operational Email on SES: Current Checkpoint

Goal: contractor email (setup, sending, events, replies) runs only on Amazon SES; zero Brevo on the contractor
side. Brevo stays only for platform/Jafar emails (`src/lib/server/email/brevo.ts`, untouched).

## State

Part 6 approved 2026-09-25. Worktree `../Ucrm-email-ses`, branch `operational-email-ses`, last commit `9ecef26`.
Steps 1–3 done and committed (3 = migration `20260925180000_operational_email_ses_only_tables.sql`, pushed live;
Raad's Brevo-era test emails deleted with Jafar's OK). pgTAP fixtures updated but not run (no local stack).

## Exact next action

Step 4: delete Raad's four Brevo leftovers in the Brevo account. The auto-mode classifier blocked the
deletes; Jafar must run them himself or allow them. Items: sender `4` (office@mail.test.upliftcontractor.com),
domains `6a926295628c23a1d7062d73` (reply.test…) and `6a92b053e1da0b7d9302b653` (mail.test…, the orphan),
inbound webhook `2158695`. Do NOT touch `contact.`/`notifications.`/`replies.upliftcontractor.com`, sender 1,
or webhook `2021984`. Ask Jafar whether `replies.upliftcontractor.com` and webhook `2021984` are still used:
the webhook points at the deleted `/api/webhooks/brevo/inbound/...` route. Then step 5.

## Blockers

Live test (step 5) needs `cloudflared tunnel run` and Jafar sending replies. Raad currently has no receiving
row; step 5's fresh Set up creates it. AWS: `aws --profile ucrm` (`aws sso login --sso-session ucrm`).
Copy sibling files-media migrations untracked into worktree before `db push`.
Known gap: org purge leaves Marketing CloudFront click-domain resources (marketing campaign's concern).

Resume: `continue operational email ses`.
