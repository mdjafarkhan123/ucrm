# Communications Activation: Current Checkpoint

## Goal

Make Communications deliver email and SMS through a GHL-style unified inbox and provide safe delivery channels
to dependent products such as Marketing. Email is live; SMS Stages 1–9 and 6D (MMS) are all done and committed.
Everything stays dark (no live traffic) until a country launch gate passes.

## Active part

None. Every buildable, testable-against-mocks unit of SMS work is done and committed (Stages 1–9, including
6D-1/6D-2/6D-3 MMS — commit `28c801a`). Nothing dependency-ready remains to build alone; all real remaining
work needs a live registered business first (Stage 9's hard constraint).

## Exact next action

Paused. Jafar is handling business registration (Bangladesh) directly and will come back when it's done.
When he returns, resume here and do the live proof this constraint has been blocking:

1. Real end-to-end SMS/MMS send (compose → enqueue → Twilio → delivery receipt) in the browser, not just
   isolated test rows.
2. Stage 8 live proof (price + usage-window reconciliation against real Twilio billing data).
3. Stage 9 real Trust Hub submission (actually register the platform's own ISV profile, then a contractor).
4. Ask Jafar to create the live Twilio Event Streams Sink for Stage 9D (his action, not code — can happen
   any time, does not need to wait for the business registration).

No code work is queued before then.

Pre-existing and unrelated to this campaign, found in an earlier session, do not re-investigate: a full local
pgTAP run and a full `vitest run` both surface dozens of failures outside communications (stale Stage-1 SMS
fixture, quotes/team/settings specs, website_chat/jobs/quotes pgTAP) — confirmed unrelated by running the
affected files individually.

## Constraint

Neither the platform nor any contractor has a real registered business yet. A2P 10DLC cannot complete, and no
live Twilio send/price data can ever exist, until one does. Never spend real money firing placeholder data at
Twilio's live API. The SMS outbox wake cron (`dispatch_communication_sms_outbox_wake`) is deliberately left
inactive in dev for this same reason — do not enable it without Jafar's explicit sign-off. Do not flip any
organization's SMS sender to a fake `ready` state to work around this.

Resume: `read memory and continue — communications-activation`.
