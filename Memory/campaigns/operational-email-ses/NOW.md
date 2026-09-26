# Operational Email on SES: Current Checkpoint

Goal: contractor email runs only on Amazon SES; Brevo stays only for platform/Jafar email (`src/lib/server/email/brevo.ts`).

## State

Part 4b (ROADMAP) approved 2026-09-26; decisions promoted to `docs/contractor-email-contract.md` "Conversations and
replies". A (shared receipt rule) live-proven; B (spam/virus quarantine) committed. In-Reply-To proven live for
Marketing (Simple) sends; operational (Raw) not yet. SES region is us-east-1.

## Exact next action

4b step C: make mail./news.<root> receive. (1) MX + teardown for both, relax `assertSubdomainNotOccupied`
allow-lists (`[]` today), update pinned activation specs. (2) New migration extending
`record_communication_inbound_message` (latest def `20260925180000`): today it matches only `purpose='receiving'`
domains, else returns NULL and the worker deletes silently. Match order: alias -> In-Reply-To (delivery intent or
`marketing_campaign_recipients.provider_message_id`) -> sender vs org contacts -> review queue; never guess.
Then D: live-prove Marketing + operational From-replies and an operational In-Reply-To link on Raad.

## Blockers

Needs Jafar for D: dev server + `cloudflared tunnel run`, Raad-owner sign-in, Gmail replies. AWS: `aws --profile
ucrm` (renew `aws sso login --sso-session ucrm`). A Raad review-queue test row ("Shared rule check") can be dismissed.

Resume: `continue operational email ses`.
