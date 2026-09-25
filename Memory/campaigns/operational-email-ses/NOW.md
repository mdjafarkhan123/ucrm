# Operational Email on SES: Current Checkpoint

Goal: contractor email (setup, sending, events, replies) runs only on Amazon SES; zero Brevo on the contractor
side. Brevo stays only for platform/Jafar emails (`src/lib/server/email/brevo.ts`, untouched).

## State

Part 6 steps 1–4 done; all work is on `main` in the main folder. Step 5 (live test on Raad) in progress:
Raad's Everyday email + replies show **Ready** (reply.test MX → SES). Outbound send is **proven live**: test 2 to
client Greenfield Property Group (`dev.jafarkhan+part8@gmail.com`) was accepted by SES, after two fixes
(`1774095`, `d6836eb`: skipped duplicate-version migration, then ambiguous `organization_id` in the claim).
Jafar replied from Gmail; the MIME reached S3 (`ucrm-ses-inbound-mime/18f0d717…/`) but was NOT ingested.

## Exact next action

Fix the receipt-rule shape in `src/lib/server/communications/ses.ts` (`desiredReceiptRule` + the `matches`
check in `reconcileSesReceiptRule`): use ONE `S3Action` carrying `TopicArn`, not S3Action + a separate
`SNSAction`. The worker/parser (`ses-inbound-email.ts`) correctly expects the S3 action's notification
(`receipt.action.type = 'S3'`, bucketName, objectKey); the separate SNS action sends `type: 'SNS'`, so every
reply is counted `invalid`, and it also bounces mail over 150 KB (see
`docs/research/amazon-ses-contractor-email-inbound-architecture-2026-09-19.md` line 23). Add a spec for the rule
shape, then press Check on Raad's Email card (Jafar panel → Communications) to update the live rule, and have
Jafar reply again. Jafar's first reply's SQS message goes to `ucrm-ses-inbound-dlq` after 5 receives; it can be
discarded (test data). Then the roadmap Part 4 gate cases.

## Follow-ups found in step 5 (small, do after the live test)

- `ManualEmailDialog.svelte:153` preview says "Delivery is currently disabled" — stale hard-coded text; remove.
- Manual send toast says "Email sent" when it is only queued; say "queued" until SES accepts.
- A failed Check (409 `subdomain_occupied`) showed no visible error on the Jafar Email card.

## Blockers

Needs Jafar: dev server + `cloudflared tunnel run`, his Jafar-panel and Raad-owner browser sign-ins, and a Gmail
reply. AWS: `aws --profile ucrm` (renew with `aws sso login --sso-session ucrm`).
Known gap: org purge leaves Marketing CloudFront click-domain resources (marketing campaign's concern).

Resume: `continue operational email ses`.
