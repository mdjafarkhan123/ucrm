# Communications Activation: Current Checkpoint

## Goal

Make Communications deliver email and SMS through a GHL-style unified inbox and provide safe delivery channels
to dependent products such as Marketing. Email is live; SMS Stages 1–5 done (Stage 5: signed status + inbound
webhooks, both committed). Everything stays dark (no send UI, no live traffic) until a country launch gate
passes.

## Active part

**Stage 6 — SMS in Conversations.** Not started. Spec: `docs/communications-a2-implementation-plan.md` §6 +
the approved product/UI blueprint (`docs/unified-inbox-behavior-contract.md` and the A2 product-planning
sequence item 4 in ROADMAP.md). Outcome: extend the existing mixed-channel inbox (read, grouping, composer,
Realtime) with SMS — sender choice, segment/cost estimate, quiet-hours, bubbles, scheduled/failure states,
identity resolution, MMS/secure-link — without duplicating snippets/attachments/assignment/followers/unread
that already work for email.

## Exact next action

Before writing any code: load the `jobber` skill (Conversations/inbox behavior) and re-read the existing email
Conversations implementation (inbox list, thread view, composer, Realtime wiring) to find the exact seams SMS
plugs into. Then split Stage 6 into independently-verifiable parts (data/API first, then UI, mirroring how
Stage 2C/3C/4 were split) and get Jafar's nod on the split before coding, since this part is large enough to
span sessions.

## Constraint

A2P 10DLC cannot be completed for Jafar's test org; nothing actually sends. Provider-owned actions stay
Jafar's. Stage 4's wake stays inactive (cron created, not scheduled) until the launch gate.

Resume: `read memory and continue — communications-activation`.
