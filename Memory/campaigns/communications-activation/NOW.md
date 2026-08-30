# Communications Activation: Current Checkpoint

## Goal

Make Communications deliver email, then SMS, then marketing, with a unified inbox that feels instant like
WhatsApp/Messenger/GHL.

## Current position

Email is complete and accepted by Jafar. Outbound delivery is approximately 3 seconds; the app's inbound
realtime path is approximately 1 second. The observed 24–58 second reply delay is external Gmail-to-Brevo
routing. Jafar confirmed deletion of legacy Brevo webhook 2021873 on 2026-08-30.

## Exact next action

Jafar chooses the first SMS use cases; recommended: appointment reminder, “on my way,” and missed-call
auto-reply. Start Twilio 10DLC registration immediately after that decision. In parallel, execute
contractor-settings 6A and its approved 6B vertical slice; A2 SMS implementation starts after 6B and 10DLC
approval.

## Blockers

A2 is not scoped. It depends on the initial-use-case decision, Automation 6B, and carrier 10DLC approval.

## Essential pointers

- `Memory/campaigns/communications-activation/ROADMAP.md` — A2 dependencies and SMS question Q5
- `Memory/campaigns/contractor-settings/NOW.md` — current dependency-ready Automation task

Resume: `read memory and continue — communications-activation`.
