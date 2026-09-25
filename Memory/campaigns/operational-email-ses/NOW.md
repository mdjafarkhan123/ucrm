# Operational Email on SES: Current Checkpoint

Goal: contractor email (setup, sending, events, replies) runs only on Amazon SES; zero Brevo on the contractor
side. Brevo stays only for platform/Jafar emails (`src/lib/server/email/brevo.ts`, untouched).

## State

Part 6 step 5 on Raad (all on `main`): send and every Part 4 reply case proven live except the Marketing-reply
case (see ROADMAP Part 4). Greenfield (`e10eed2b…`) carries two labelled test emails (Jafar's Gmail and
push-test@mail.test…); filed test messages reference them, so they stay.

Speed (dev tunnel): SNS push wake is intermittent -- SNS logged failed HTTPS attempts that never reached the
tunnel; the one-minute cron backstops it (worst case ~60 s). Cause unconfirmed. Raise at production planning:
a continuously long-polling SQS worker container (standard consumer pattern) instead of relying on the push.
Re-measure on the production endpoint either way.

## Exact next action

Marketing-reply case with Jafar: send a Raad Marketing campaign to a client whose email is his Gmail, he
replies, verify it lands in the right Conversation with Campaign origin. Then the ROADMAP "Step 5 follow-ups".

## Blockers

Needs Jafar: dev server + `cloudflared tunnel run`, Raad-owner browser sign-in, a Gmail reply. AWS: `aws --profile
ucrm` (renew with `aws sso login --sso-session ucrm`).

Resume: `continue operational email ses`.
