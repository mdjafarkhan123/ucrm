# Operational Email on SES: Current Checkpoint

Goal: contractor email runs only on Amazon SES; Brevo stays only for platform/Jafar email (`src/lib/server/email/brevo.ts`).

## State

All of Part 7 (7A schema/claim-finalize, 7B Jafar price-setting UI, 7C contractor "add credit" messaging) is
built and committed. A real rate is live ($0.675 USD/1,000, set 2026-09-26). The usage-summary mixing bug is
fixed and committed (see part packet). Part 7's own completion gate is not yet met: no organization has
actually gone over-allowance for real, so the charge path is proven only by a local manual SQL exercise, not
a live SES send. Nothing else in this campaign is dependency-ready to build alone right now.

## Exact next action

Nothing is dependency-ready to build alone until a real contractor organization goes over its email
allowance with the published rate live, so the full charge -> defer/insufficient-balance -> "Add credit"
path can be browser-verified end to end against a real send. That needs either a real contractor sending
enough optional email past its allowance, or Jafar's go-ahead to manually drive one organization over its
allowance on the real database to prove the gate.

## Notes that change the next action

- Another agent may be working a different campaign in this same folder; commit only operational-email files.
- `npm run check` OOMs; run `NODE_OPTIONS=--max-old-space-size=8192 npx svelte-check --tsconfig ./tsconfig.json`.
  Three pre-existing "union type too complex" errors are not ours.
- Regenerating `db:types` reformats the whole file; run `npx prettier --write src/lib/database.types.ts` after,
  and redirect the CLI's own stderr away from the output file (`npx supabase gen types typescript --linked
  2>/dev/null > src/lib/database.types.ts`) or a stray WARN line corrupts it.
- Raad's office, sales and finance test roles have no `conversations.send` permission (found in 5A testing,
  unverified whether intended).

## Open asks for Jafar

- `ucrm-ses-inbound-dlq` still holds one AWS "setup notification" test ping (2026-09-25, recipient@example.com).
  Harmless junk; delete only with Jafar's yes.
- Cloudflare DNS records for the deleted Brevo `notifications.upliftcontractor.com` may remain; harmless.

## Blockers

AWS: `aws --profile ucrm` (renew `aws sso login --sso-session ucrm`). Real usage: needs a real organization to
exceed its email allowance.

Resume: `continue operational email ses`.
