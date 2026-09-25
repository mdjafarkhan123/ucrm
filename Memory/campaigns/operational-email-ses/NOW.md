# Operational Email on SES: Current Checkpoint

Goal: contractor email (setup, sending, events, replies) runs only on Amazon SES; zero Brevo on the contractor
side. Brevo stays only for platform/Jafar emails (`src/lib/server/email/brevo.ts`, untouched).

## State

Part 6 step 5 (live test on Raad, all on `main`): outbound send and reply ingestion proven live; Jafar's Gmail
replies land in Needs review (sent from an address not on Greenfield, correct by contract).

## Exact next action

Replies ingest live (`c0670fa`); instant pickup built (`d7a4d20`, SNS HTTPS subscription `025ff623…` to
`https://app.upliftcontractor.com/api/webhooks/ses-inbound`). Measured S3 → inbound row: 3 s, 34 s, 33 s, 4 s; slow
cases were SNS push attempts that never reached the app via the dev tunnel (cause unconfirmed; creating an IAM
role for SNS delivery-status logs was blocked by the permission classifier; Cloudflare token lacks analytics).
After those tests the subscription got a fast-retry DeliveryPolicy (2 immediate + 1 s exponential, 10 retries) —
not yet measured. `dev.jafarkhan@gmail.com` was added (SQL, test data) as a non-primary email on Greenfield
(`c8e1f036…`). Laptop clock fixed (chrony `authselectmode ignore`).
Next: Jafar replies once more from Gmail to the Raad test email; verify the row is `accepted` with Greenfield's
client_id and measure seconds; then roadmap Part 4 gate cases. Re-measure speed on the production endpoint.

Small follow-ups from step 5: ROADMAP.md "Step 5 follow-ups" (do after the live test).

## Blockers

Needs Jafar: dev server + `cloudflared tunnel run`, his Jafar-panel and Raad-owner browser sign-ins, and a Gmail
reply. AWS: `aws --profile ucrm` (renew with `aws sso login --sso-session ucrm`).

Resume: `continue operational email ses`.
