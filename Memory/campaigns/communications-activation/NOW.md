# Communications Activation: Current Checkpoint

## Goal

Make Communications deliver email and SMS through a GHL-style unified inbox and provide safe delivery channels
to dependent products such as Marketing. Email is live; SMS Stages 1–9 and 6D (MMS) are all done and committed.
Everything stays dark (no live traffic) until a country launch gate passes.

## Active part

**Global texting (Stage 10), approved 2026-10-22.** Plan: `docs/global-sms-behavior-contract.md` (core agreement —
read it). Follow GHL: every country with Twilio stock except Asia; rules read live from Twilio, never hardcoded.
Research: `docs/research/global-sms-country-requirements-2026-10-22.md`. Platform ISV profile
`BU0a5a8f75e733bf8f1020e8d923a017f5` approved 2026-10-19.

## Exact next action

Part 1 server foundation (country rules module + ISV settings) on branch `claude/comms-global-sms`. Pencil designs
for Add number, Compliance, per-number readiness and Jafar country controls run as separate design sessions before
Parts 2–6 UI. Real purchases/registrations wait for the first paying customer and Jafar's yes.

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
