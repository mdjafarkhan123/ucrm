# Operational Email on SES: Current Checkpoint

Goal: contractor email (setup, sending, events, replies) runs only on Amazon SES; zero Brevo on the contractor
side. Brevo stays only for platform/Jafar emails (`src/lib/server/email/brevo.ts`, untouched).

## State

Part 6 approved by Jafar 2026-09-25. Worktree `../Ucrm-email-ses`, branch `operational-email-ses`, last commit
`beb3dda`. Done: step 1 (replies folded into Set up/Check), 2a (sending SES-only), 2b (owner routes SES-only;
Remove now tears down sending + replies via `teardownOperationalDomain`), 2c (Brevo webhooks/inbound gone),
2d prep (`ses-organization-cleanup.ts` + SES tenant/config-set delete helpers, not yet wired).

## Exact next action

Finish step 2d: apply `Memory/campaigns/operational-email-ses/closure-cron-wip.patch` in the worktree
(`git apply`), rewrite the provider tests in `organization-closure-cron.spec.ts` for SES, then delete
`src/lib/server/communications/brevo.ts` + spec, Brevo inbound helpers in `email/env.ts`, contractor Brevo env
keys (keep `BREVO_API_KEY`), and fix Brevo comments in settings/cleanup routes, email-health, twilio inbound.
Delete the patch file once applied. Then step 3.

## Step 3 needs (DB migration)

Tables SES-only (provider checks/defaults; `record_communication_inbound_message` default 'brevo'); retiring
a sending row via `finalize_communication_email_domain_removal` must also retire the org's receiving row;
`apply_organization_purge` returns one `{kind:'ses_organization', provider_id:<org id>}` instead of Brevo ids;
check for pending Brevo purge receipts; delete Raad's Brevo rows.

## Blockers

Live test (step 5) needs `cloudflared tunnel run` and Jafar sending replies. AWS: `aws --profile ucrm`
(`aws sso login --sso-session ucrm`). Copy sibling files-media migrations untracked into worktree before `db push`.
Known gap: org purge leaves Marketing CloudFront click-domain resources (marketing campaign's concern).

Resume: `continue operational email ses`.
