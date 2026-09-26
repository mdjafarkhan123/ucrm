# Operational Email on SES: Current Checkpoint

Goal: contractor email runs only on Amazon SES; Brevo stays only for platform/Jafar email (`src/lib/server/email/brevo.ts`).

## State

Part 4b (ROADMAP; contract "Conversations and replies"). A live-proven, B committed, C code-complete and
unit-tested: the worker passes `target_sender_authenticated`; Set up/Check writes the SES inbound MX on
mail.<root> / news.<root> once each identity verifies (`routeSendingRepliesToSes`); operational Remove and org
purge (`teardownMarketingDomain`) delete it first. Not yet run against Raad: no real MX exists until an owner
runs Check on Raad's everyday and Marketing domains. SES region us-east-1.

## Exact next action

D: with Jafar, run Check on Raad's everyday email and Marketing domains (this writes the two MX records live),
confirm with `dig MX mail.<root>` / `news.<root>`, then live-prove a Gmail reply to the From address of an
operational email and a Marketing email, plus an operational In-Reply-To link, all landing in Raad's inbox.

## Blockers

Needs Jafar for D: dev server + `cloudflared tunnel run`, Raad-owner sign-in, Gmail replies. AWS: `aws --profile
ucrm` (renew `aws sso login --sso-session ucrm`). A Raad review-queue test row ("Shared rule check") can be dismissed.

Resume: `continue operational email ses`.
