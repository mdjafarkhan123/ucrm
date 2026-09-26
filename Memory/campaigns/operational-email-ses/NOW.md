# Operational Email on SES: Current Checkpoint

Goal: contractor email runs only on Amazon SES; Brevo stays only for platform/Jafar email (`src/lib/server/email/brevo.ts`).

## State

Part 4b (ROADMAP; contract "Conversations and replies"). A live-proven, B committed. C database half pushed live:
`20260926140000` rewrote `record_communication_inbound_message` (From-reply matching, new optional
`target_sender_authenticated`); all 8 cases verified in a rolled-back DO block on Raad data. Nothing receives on
mail./news. yet (no MX), so no live behaviour changed. SES region us-east-1.

## Exact next action

Finish 4b C: (1) worker passes `target_sender_authenticated` = SES `receipt.dkimVerdict` or `dmarcVerdict`
status PASS (add both to the schema in `ses-inbound-email.ts`; spec it); regenerate `database.types.ts`.
(2) Set up writes MX -> `sesInboundMxTarget()` on mail.<root> (`operational-domain-activation.ts`, after the
sending identity verifies) and news.<root> (`marketing-domain-activation.ts`); relax their
`assertSubdomainNotOccupied` allow-lists; teardown deletes both MX; update pinned specs. Sending rows must keep
`inbound_mx_status='unchecked'` (table check). Then D: live-prove Marketing + operational From-replies and an
operational In-Reply-To link on Raad.

## Blockers

Needs Jafar for D: dev server + `cloudflared tunnel run`, Raad-owner sign-in, Gmail replies. AWS: `aws --profile
ucrm` (renew `aws sso login --sso-session ucrm`). A Raad review-queue test row ("Shared rule check") can be dismissed.

Resume: `continue operational email ses`.
