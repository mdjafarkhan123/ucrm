# Operational Email on SES: Current Checkpoint

## Goal

Contractor operational email (setup, sending, events, replies) runs on Amazon SES instead of Brevo.

## State

Part 1 done 2026-09-24: Jafar approved the setup screen designs (contract section "Email setup screens").
Start rule met (marketing SES work committed). All work happens in worktree `../Ucrm-email-ses` on branch
`operational-email-ses`; merge the shared `ses.ts`/`ses-env.ts` overlap at the end.

## Exact next action

Start Part 2 in the worktree (Part 7, email credit, is approved and can follow any time): owner "Set up" on the Everyday email row creates SES sending + receiving identities
(+ MAIL FROM, config set in the org's existing SES tenant) via Cloudflare, reusing the Marketing activation path
(`marketing-domain-activation.ts`, `dns-reconcile.ts`) instead of the Brevo one (`email-domain-activation.ts`).
Gate: Raad re-activated and verified live.

## Blockers

Part 4 needs Jafar's approval before any AWS resource is created.

## Pointers

`docs/contractor-email-contract.md` ("Email setup screens", "Domain provisioning"); architecture research doc in
`ROADMAP.md`. Resume: `continue operational email ses`.
