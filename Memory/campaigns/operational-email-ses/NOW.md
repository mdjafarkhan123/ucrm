# Operational Email on SES: Current Checkpoint

Goal: contractor email runs only on Amazon SES; Brevo stays only for platform/Jafar email (`src/lib/server/email/brevo.ts`).

## State

Part 6 step 5 on Raad: every Part 4 reply case proven live except Marketing-reply to From (bounces: no MX on
mail./news.). In-Reply-To linking committed `273e6fd`; live data proves Simple sends' In-Reply-To bare id equals the
stored SendEmail MessageId (marketing recipients). Raw (operational) still unproven live; SES docs say SES overrides
any Message-ID, so nodemailer's own id is replaced. Keep Greenfield's (`e10eed2b…`) two test emails.

Research 2026-09-26 (primary sources, verified): SES quotas page -- 200 rules per rule set, 500 recipients per rule,
NOT adjustable; 10,000 identities/region (ask AWS); 10,000 config sets (not adjustable). `ses.ts` creates ONE rule per
org => hard ceiling ~200 orgs receiving replies. A rule with no Recipients applies to all verified identities
(documented). GHL puts MX on the sending subdomain; Microsoft + M3AAWG say From should receive. SES scans
(`ScanEnabled: true`) but the worker ignores spam/virus verdicts. The bounced Gmail got only one test email (unique
subject) while the other Gmail's reply to the same campaign worked: cause is client-side, still unknown.

## Exact next action

Get Jafar's answer on: (1) make mail./news. receive + match order alias -> In-Reply-To -> sender -> hold;
(2) replace per-org rules with one catch-all rule (app routes by recipient); (3) quarantine spam/virus FAIL.
Then implement. Draft impl: MX + recipients for mail./news.; relax `assertSubdomainNotOccupied` allow-lists; teardown;
extend `record_communication_inbound_message` (latest `20260925180000`) beyond `purpose='receiving'` (others return
NULL and the worker deletes silently). Live-prove Marketing + operational From-replies.

## Blockers

Needs Jafar: dev server + `cloudflared tunnel run`, Raad-owner sign-in, Gmail replies. AWS: `aws --profile ucrm`
(renew `aws sso login --sso-session ucrm`).

Resume: `continue operational email ses`.
