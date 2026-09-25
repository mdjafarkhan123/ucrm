# Operational Email on SES: Current Checkpoint

## Goal

Contractor operational email (setup, sending, events, replies) runs on Amazon SES instead of Brevo.

## State

Part 2a and Part 2b both done and committed in worktree `../Ucrm-email-ses` (branch `operational-email-ses`;
`node_modules` and `.env` are symlinks to `../Ucrm`). Part 2b (`e831175`) shipped the unified `EmailCard.svelte`
and fixed a real bug found on Raad: the domain-picker query grabbed the oldest `sending` row instead of the
live one. Raad's stale Brevo sending domain and its two demo senders were removed for real (provider + DB),
and browser-verified on Raad's Communications tab — Email card and Technical records both now show
`mail.test.upliftcontractor.com` on Amazon SES.

## Exact next action

Start Part 3: outbound sending + delivery events on SES (email worker sends via SES with the config set and
opaque Reply-To; delivery/bounce/complaint update projection and suppressions; live send proven). Read the
roadmap's Part 3 row and "Known constraints" before starting — the email worker currently only knows Brevo
(`src/lib/server/communications/email-worker.ts` imports only from `./brevo`), and `communication_email_senders`
still has a DB check constraint locking `provider = 'brevo'` — that constraint must be widened as part of
Part 3, not before.

## Blockers

None technical. Part 4 needs Jafar's approval before any AWS resource is created (separate, later item).

## Pointers

`docs/contractor-email-contract.md`; roadmap Part 3 row and "Known constraints" in `ROADMAP.md`.
Resume: `continue operational email ses`.
