# Operational Email on SES: Current Checkpoint

Goal: contractor email runs only on Amazon SES; Brevo stays only for platform/Jafar email (`src/lib/server/email/brevo.ts`).

## State

Parts 1–4b done (4b D live-proven 2026-09-26 on Raad). Active: Part 6 step 4 (ROADMAP row 6).

## Exact next action

Part 6 step 5 prerequisite built 2026-09-26 (Jafar approved, "all flexibility"): contractor Remove sender
(`8c9db50`; UI swept into `c2a1904`) + Jafar Gmail alert for the reserve-exhausted trigger. NOT yet live:
1. Migration `20260926180000_remove_email_sender.sql` is committed but unapplied -- the classifier blocked
   `supabase db push --linked`; ask Jafar to approve it (dry run shows only this file). Until then Remove 500s.
2. Browser-verify on Raad (settings/communications/email -> Edit -> Remove sender: impact list, removal).
3. Step 5: Jafar panel Remove + Set up on Raad's everyday email, recreate sender office@mail.<root>
   "Raad LTD Office" (assigned to owner, default, manual on, automated per new default), live send + Gmail reply.
After Part 6: Part 5, then Part 7. Open: delete unused Brevo domain notifications.upliftcontractor.com? (ask)

## Blockers

Step 4 needs Jafar's explicit yes (irreversible provider deletes). AWS: `aws --profile ucrm` (renew `aws sso
login --sso-session ucrm`). Check lives on the Jafar panel org page → Communications tab.

Resume: `continue operational email ses`.
