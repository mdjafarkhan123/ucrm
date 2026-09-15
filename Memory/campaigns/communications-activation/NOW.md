# Communications Activation: Current Checkpoint

## Goal

Make Communications deliver email and SMS through a GHL-style unified inbox and provide safe delivery channels
to dependent products such as Marketing. Email is live; SMS Stages 1–5 done. Stage 6 (SMS in Conversations)
split into 6A/6B/6C, Jafar approved 2026-09-15. 6A committed (66bda26). Everything stays dark (no live traffic)
until a country launch gate passes.

## Active part

**Stage 6C — Thread rendering + polish.** Depends on 6B (done, committed d5c3859). Not yet started. Per
ROADMAP.md: SMS chat bubbles, delivery ticks (sent/delivered/failed), scheduled-message indicator, MMS
attachments, phone-based identity resolution when a client isn't yet matched. `+page.svelte`'s
`activeChannel` switch is currently binary (email/website_chat) and needs the SMS case added to bubble
rendering.

Correction for future sessions: the `office` test role has no `conversations.*` permission (only owner/admin
do, by design) and cannot open Communications at all — use an owner/admin login for any Communications
browser check, not `office`.

## Exact next action

Scope 6C: read the current message-bubble rendering in `+page.svelte` (how email/website_chat bubbles are
built) and `docs/communications-a2-implementation-plan.md` §4/§6 for the approved SMS bubble/ticks/MMS
behavior, then plan the smallest correct implementation before coding.

## Constraint

A2P 10DLC cannot be completed for Jafar's test org; nothing actually sends. Provider-owned actions stay
Jafar's.

Resume: `read memory and continue — communications-activation`.
