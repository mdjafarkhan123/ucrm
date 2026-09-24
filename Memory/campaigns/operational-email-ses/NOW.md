# Operational Email on SES: Current Checkpoint

## Goal

Contractor operational email (setup, sending, events, replies) runs on Amazon SES instead of Brevo.

## State

Part 2a done and live-verified on Raad 2026-09-25 (mail.test.upliftcontractor.com on SES; reply row still on
Brevo by design). Work is in worktree `../Ucrm-email-ses` (branch `operational-email-ses`; `node_modules` and
`.env` are symlinks to `../Ucrm`). The agent may not type passwords: Jafar signs in to `localhost:5174/jafar`
when a live check needs the owner panel (`npx vite dev --port 5174` in the worktree).

## Exact next action

Build Part 2b: the approved owner Email card (contract "Email setup screens") replacing
`EmailDomainActions.svelte` + `MarketingDomainActions.svelte` in `CommunicationsWorkspace.svelte`. Load the design,
svelte, and bits-ui skills first. Gate: browser-verified on Raad.

## Blockers

Part 4 needs Jafar's approval before any AWS resource is created.

## Pointers

`docs/contractor-email-contract.md` ("Email setup screens", "Domain provisioning"); ROADMAP known constraints.
Resume: `continue operational email ses`.
