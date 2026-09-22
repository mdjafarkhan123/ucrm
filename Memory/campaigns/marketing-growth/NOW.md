# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

M1-M3 complete. SES production access APPROVED (console, 2026-09-22): 50,000 emails/24h, 14/sec, account
`881776924275` "UCRM Production Workloads", us-east-1.

M4 stage 1 (per-org SES sending identity) is **committed** as `97f94b2`. It still has never run against real AWS
or a real DNS zone and waits on Jafar's IAM user and `AWS_SES_*` values.

M4 stage 2 (launch snapshot + Marketing allowance + `marketing_launch_campaign`) is **done and committed** as
`7fc6223`. Migration `20260922160000` is applied to the live database (Jafar approved 2026-09-22), types are
regenerated, and `launchCampaign` is in `src/lib/server/marketing/campaigns.ts`. Nothing calls it yet by design.

M4 stage 3 (the Marketing dispatcher) is **done and committed** as `e8889dc`. The migration
`supabase/migrations/20260922170000_marketing_campaign_dispatcher.sql` is applied to the linked remote
database and `database.types.ts` is regenerated. All of stage 3's TS code is in: `sendMarketingEmail`
(ses.ts), `src/lib/server/marketing/dispatcher.ts` (+ `dispatcher.spec.ts`, 11 passing tests), the internal
worker route, and the `delivery-options.ts` derived-From-address fix. Every existing test still passes and
`tsc --noEmit` shows no new errors. Stage 3 is unproven against real AWS.

Unrelated: ~75 quote/settings/team unit tests fail on this branch. They fail identically without any of this
work and belong to the in-flight files-media Quote adoption, not to Marketing.

## Exact next action

Stages 1-3 are all committed and code-complete. Ask Jafar whether to build stage 4 (the SES event consumer)
ahead of AWS credentials the same way stage 3 was approved, or pause here. Stages 1 and 3 cannot be proven
until Jafar supplies the AWS IAM user + `AWS_SES_*` values and, for stage 3's worker route, the
`communications_marketing_worker_target_url` Vault secret.

## Blockers

Stage 1 cannot be proven without the AWS IAM user plus `AWS_SES_*` env values (Jafar), and the first
live DNS run against a real contractor domain needs a separate direct go-ahead. M9 (SMS marketing) stays blocked
until Communications A2 passes live SMS gates.

## Pointers

Part packet: `Memory/campaigns/marketing-growth/parts/M4.md`. Plan: `docs/marketing-first-release-plan.md`
(§2 provider boundary, §3 M4). Blueprint: `docs/marketing-product-blueprint.md` (§8, §9, §20).
AWS: SSO `https://d-90667ef85d.awsapps.com/start/#/` -> "UCRM Production Workloads" -> AdministratorAccess
-> SES (us-east-1); CLI profile `ucrm`, re-auth `aws sso login --sso-session ucrm`.

Resume: `continue marketing growth` -- ask Jafar about starting stage 4, or wait for AWS credentials.
