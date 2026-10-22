# Communications Activation: Current Checkpoint

## Goal

Make Communications deliver email and SMS through a GHL-style unified inbox and provide safe delivery channels
to dependent products such as Marketing. Email is live; SMS Stages 1–9 and 6D (MMS) are all done and committed.
Everything stays dark (no live traffic) until a country launch gate passes.

## Active part

**Global countries — planning (2026-10-22).** Jafar: no registered business yet; make the app launch-ready for
contractors worldwide (US, CA, AU, NZ, BR, UK…) now; real end-to-end proof waits for the first paying customer.
Platform ISV Primary Customer Profile `BU0a5a8f75e733bf8f1020e8d923a017f5` approved 2026-10-19 (not yet in app config).
Today the app is US-only (registration country fixed to US, 10DLC only, no number search/purchase, no bundles).
Research: `docs/research/global-sms-country-requirements-2026-10-22.md`.

## Exact next action

Jafar answers the six product choices in the research file's "Open questions", then write the global-countries
plan (behavior + build order) for his approval. No code before that approval.

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
