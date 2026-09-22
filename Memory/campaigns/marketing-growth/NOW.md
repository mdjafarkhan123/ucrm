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
Read `Memory/campaigns/marketing-growth/parts/M4.md` before continuing.

Unrelated: ~75 quote/settings/team unit tests fail on this branch. They fail identically without any of this
work and belong to the in-flight files-media Quote adoption, not to Marketing.

## Exact next action

Start stage 3, the Marketing dispatcher (claim/finalize RPC pair over `marketing_campaign_recipients`, internal
worker route on `runBoundedDrain`, lease `communications-marketing-outbox`). Stage 3 needs the SES call to be
real, so settle the From-address decision recorded at the end of `parts/M4.md` first, and note that stage 3
cannot be proven end to end until Jafar supplies the `AWS_SES_*` values stage 1 is waiting on.

## Blockers

Stage 1 cannot be proven without the AWS IAM user plus `AWS_SES_*` env values (Jafar), and the first
live DNS run against a real contractor domain needs a separate direct go-ahead. M9 (SMS marketing) stays blocked
until Communications A2 passes live SMS gates.

## Pointers

Part packet: `Memory/campaigns/marketing-growth/parts/M4.md`. Plan: `docs/marketing-first-release-plan.md`
(§2 provider boundary, §3 M4). Blueprint: `docs/marketing-product-blueprint.md` (§8, §9, §20).
AWS: SSO `https://d-90667ef85d.awsapps.com/start/#/` -> "UCRM Production Workloads" -> AdministratorAccess
-> SES (us-east-1); CLI profile `ucrm`, re-auth `aws sso login --sso-session ucrm`.

Resume: `continue marketing growth` -- read parts/M4.md, continue at the current stage.
