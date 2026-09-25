# Operational Email on SES: Current Checkpoint

Goal: contractor email (setup, sending, events, replies) runs only on Amazon SES; zero Brevo on the contractor
side. Brevo stays only for platform/Jafar emails (`src/lib/server/email/brevo.ts`, untouched).

## State

Part 6 step 5 (live test on Raad, all on `main`): outbound send proven; 2026-09-25 16:31 UTC Jafar's Gmail reply
was `accepted` onto Greenfield (reply alias → Greenfield, Gmail added there as test data). Reply acceptance done.

Speed finding (dev tunnel): the SNS push wake is intermittent. For the Gmail reply SNS logged 2 failed HTTPS
attempts and delivered on the 3rd ~45 s later (ledger `private.communication_worker_wake_ledger`); the cron
tick filed it at 21 s. Test 4 minutes later: push arrived in 1.5 s, filed in 4 s. The tunnel counted fewer errors
than SNS failures, so some attempts never reach the laptop; cause unconfirmed (no Cloudflare analytics / SNS
delivery logs). Proven alternative to raise with Jafar at production planning: a continuously long-polling SQS
worker container (no dependence on the push). Re-measure on the production endpoint either way.

## Exact next action

Roadmap Part 4 gate cases, live on Raad: duplicate, oversized attachment, expired alias, auto-response,
recovery, and a reply to a Marketing campaign email. Then the "Step 5 follow-ups" in ROADMAP.md.

## Blockers

AWS SSO token expired: Jafar runs `aws sso login --sso-session ucrm`. Needs dev server + `cloudflared tunnel run`.

Resume: `continue operational email ses`.
