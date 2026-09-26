# Operational Email on SES: Current Checkpoint

Goal: contractor email runs only on Amazon SES; Brevo stays only for platform/Jafar email (`src/lib/server/email/brevo.ts`).

## State

Parts 1–4b, 5A and 6 done. Part 5 product decisions settled with Jafar 2026-09-26 and written into
`docs/contractor-email-contract.md` → "Request lifecycle and sender fallback": a domain is required to request,
cancel only while the request waits on Jafar, never editable, re-request always allowed, and manual sends fall
back to the business address (Jobber's guarantee). 5A shipped that fallback (`1410c2a9`).

## Exact next action

Build Part 5B, the contractor request-setup flow (ROADMAP row 5B). Not yet started, nothing designed in code.
Approved screens: contract section "Email setup screens". Pieces, in this order:

1. Request table + RPCs: one non-terminal request per organization; statuses open → activating → completed,
   plus cancelled (contractor) and declined (Jafar closes with a note the contractor sees).
2. Contractor Settings → Email card at `src/routes/(app)/settings/communications/email/+page.svelte`, which
   today dead-ends at "Ask your platform owner to provision and verify a sending domain".
3. Owner Email card request block (`src/lib/components/jafar/EmailCard.svelte`): Set up prefilled with the
   requested domain, plus Close request.
4. Jafar alerting: "Waiting on you" notification (existing platform notifications feed the panel in
   `src/routes/jafar/(protected)/+page.svelte`) and an `email_setup_requested` attention reason in
   `src/routes/jafar/(protected)/organizations/+page.svelte` + `src/routes/api/jafar/organizations/+server.ts`.
5. Browser-verify the whole flow on Raad, then Part 7.

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
