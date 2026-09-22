# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

M1-M3 complete. SES production access APPROVED (console, 2026-09-22): 50,000 emails/24h, 14/sec, account
`881776924275` "UCRM Production Workloads", us-east-1.

M4 stages 1-4 are all **done and committed**: stage 1 `97f94b2` (per-org SES sending identity), stage 2
`7fc6223` (launch snapshot + Marketing allowance), stage 3 `e8889dc` (the dispatcher), stage 4 `f76c14e` (the
SES event consumer). Every stage's migration is applied to the linked remote database and
`database.types.ts` is regenerated. Stages 1, 3, and 4 have never run against real AWS.

Unrelated: ~75 quote/settings/team unit tests fail on this branch. They fail identically without any of this
work and belong to the in-flight files-media Quote adoption, not to Marketing.

## Exact next action

Nothing left to build without Jafar. Ask him for:

1. The AWS IAM user + `AWS_SES_*` values (stage 1's original ask), now also needing SQS
   `ReceiveMessage`/`DeleteMessage` permission on the `ucrm-ses-events` queue for stage 4.
2. The `communications_marketing_worker_target_url` and `communications_marketing_events_worker_target_url`
   Vault secrets once the two worker routes are deployed.

Once those exist, prove stages 1, 3, and 4 against real AWS before asking about stage 5 (cancel + test email
+ go-live UI) — that stage has not been discussed with Jafar yet.

## Blockers

Stages 1, 3, and 4 cannot be proven without the AWS IAM user plus `AWS_SES_*` env values and the two worker
Vault secrets (all Jafar). The first live DNS run against a real contractor domain needs a separate direct
go-ahead. M9 (SMS marketing) stays blocked until Communications A2 passes live SMS gates.

## Pointers

Part packet: `Memory/campaigns/marketing-growth/parts/M4.md`. Plan: `docs/marketing-first-release-plan.md`
(§2 provider boundary, §3 M4). Blueprint: `docs/marketing-product-blueprint.md` (§8, §9, §20).
AWS: SSO `https://d-90667ef85d.awsapps.com/start/#/` -> "UCRM Production Workloads" -> AdministratorAccess
-> SES (us-east-1); CLI profile `ucrm`, re-auth `aws sso login --sso-session ucrm`.

Resume: `continue marketing growth` -- nothing to build until Jafar supplies the AWS credentials and Vault
secrets above; check with him before starting stage 5.
