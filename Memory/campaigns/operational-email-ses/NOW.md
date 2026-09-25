# Operational Email on SES: Current Checkpoint

Goal: contractor email (setup, sending, events, replies) runs only on Amazon SES; zero Brevo on the contractor
side. Brevo stays only for platform/Jafar emails (`src/lib/server/email/brevo.ts`, untouched).

## State

Part 6 approved 2026-09-25. Worktree `../Ucrm-email-ses`, branch `operational-email-ses`, last commit `9ecef26`.
Steps 1–3 done and committed (3 = migration `20260925180000_operational_email_ses_only_tables.sql`, pushed live;
Raad's Brevo-era test emails deleted with Jafar's OK). pgTAP fixtures updated but not run (no local stack).

## Exact next action

Step 4 mostly done 2026-09-25: Raad's four Brevo leftovers deleted and confirmed gone. Remaining: domain
`replies.upliftcontractor.com` and inbound webhook `2021984`. No code or database row uses either, and Jafar said
all data is test ("clean, clear"), but his explicit permission covered only the four; confirm before deleting.
Keep sender 1 and `contact.`/`notifications.`. Then step 5.

## Blockers

Live test (step 5) needs `cloudflared tunnel run` and Jafar sending replies. Raad currently has no receiving
row; step 5's fresh Set up creates it. AWS: `aws --profile ucrm` (`aws sso login --sso-session ucrm`).
Copy sibling files-media migrations untracked into worktree before `db push`.
Known gap: org purge leaves Marketing CloudFront click-domain resources (marketing campaign's concern).

Resume: `continue operational email ses`.
