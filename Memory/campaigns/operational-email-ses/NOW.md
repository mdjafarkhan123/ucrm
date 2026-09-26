# Operational Email on SES: Current Checkpoint

Goal: contractor email runs only on Amazon SES; Brevo stays only for platform/Jafar email (`src/lib/server/email/brevo.ts`).

## State

Parts 1–4b, 5A and 6 done. Part 5B is BUILT and checked but NOT yet browser-verified. Design fork decided
2026-09-26: the request stores only open / cancelled / declined / fulfilled; "Setting up" and "Ready" are read
from the sending-domain rows (`src/lib/server/communications/email-setup-requests.ts`, `deriveEmailSetup`).
Shipped: table + commands + waiting view (`20260926230000_email_setup_requests.sql`), directory reason
`email_setup_requested` (`20260926231000_...`), both applied live; contractor routes
`/api/settings/communications/email-setup`, Jafar routes under `.../communications/email-setup`;
contractor card `src/lib/components/settings/EmailSetupCard.svelte`; Jafar request block in `EmailCard.svelte`;
"Waiting on you" alert raised on request (in-app only, not emailed). Unit + SQL smoke checks pass.

## Exact next action

Browser-verify 5B (Chrome extension was not connected when built; ask Jafar to reconnect it). Raad LTD already
has a VERIFIED sending domain, so its contractor card is correctly hidden and it cannot show the request states
for real. Do not tear down Raad's live domain to test. Either mock `/api/settings/communications/email-setup`
responses in the browser to check the four card states + the request dialog + Cancel, and check the Jafar
EmailCard block and the "Email setup requested" filter the same way, or ask Jafar for an org with no domain
(Jaaroweb has none; no login known). Real Raad POST should answer 409 "already has a sending domain".
Then Part 7 (see ROADMAP).

## Notes that change the next action

- Another agent is working a different campaign in this same folder; commit only operational-email files.
- `npm run check` OOMs; run `NODE_OPTIONS=--max-old-space-size=8192 npx svelte-check --tsconfig ./tsconfig.json`.
  Three pre-existing "union type too complex" errors are not ours.
- Regenerating `db:types` reformats the whole file; run `npx prettier --write src/lib/database.types.ts` after.
- Found while verifying 5A: Raad's office, sales and finance test roles have no `conversations.send` permission,
  so they cannot send customer messages at all. Unverified whether that is intended; may matter to 5B testing.

## Open asks for Jafar

- `ucrm-ses-inbound-dlq` still holds one AWS "setup notification" test ping (2026-09-25, recipient@example.com).
  Harmless junk; delete only with Jafar's yes.
- Cloudflare DNS records for the deleted Brevo `notifications.upliftcontractor.com` may remain; harmless.

## Blockers

AWS: `aws --profile ucrm` (renew `aws sso login --sso-session ucrm`).

Resume: `continue operational email ses`.
