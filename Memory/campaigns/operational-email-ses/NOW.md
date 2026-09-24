# Operational Email on SES: Current Checkpoint

## Goal

Contractor operational email (setup, sending, events, replies) runs on Amazon SES instead of Brevo.

## State

Part 2 split into 2a (backend) and 2b (owner Email card UI). 2a code committed `174a8ec` in worktree
`../Ucrm-email-ses` (branch `operational-email-ses`; `node_modules` and `.env` are symlinks to `../Ucrm`).
Tests pass. Raad's DNS before the live run is saved outside the repo (Cloudflare can re-export it).

## Exact next action

Live 2a gate: run the worktree app on port 5174 (`npx vite dev --port 5174`); Jafar signs in at
`localhost:5174/jafar` (the agent may not type passwords). Then call
`POST /api/jafar/organizations/<Raad id>/communications/domains/activate` with root `test.upliftcontractor.com`,
recheck until `mail.test` shows verified on SES, and confirm Raad can still send (Brevo still sends until Part 3).
Then build 2b.

## Blockers

Part 4 needs Jafar's approval before any AWS resource is created.

## Pointers

`docs/contractor-email-contract.md` ("Email setup screens", "Domain provisioning"); ROADMAP known constraints.
Resume: `continue operational email ses`.
