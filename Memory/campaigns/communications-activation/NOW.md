# Communications Activation: Current Checkpoint

## Goal

Make Communications deliver email and SMS through a GHL-style unified inbox and provide safe delivery channels
to dependent products such as Marketing. Email is live; SMS Stages 1–6 done (6A/6B/6C committed: 66bda26,
d5c3859, 745bc8e). Everything stays dark (no live traffic) until a country launch gate passes.

## Active part

**Stage 7 — SMS in Automation.** Depends on Stage 6 (done). Not yet started. Per
`docs/communications-a2-implementation-plan.md` §7: add **Send SMS** to the existing typed action catalog,
recipe validator, editor, summary rail, immutable versions and worker, using the same SMS enqueue command and
live eligibility gates as Conversations. Automation tests are real sends restricted to the authorized user's
verified team phone. Keep the 50-step ceiling; no branching/AI writing/Manual SMS/automated MMS/marketing.

Deferred, not blocking: **6D MMS** (pictures in Conversations) — genuinely unbuilt on both sides (no Twilio
media parsing, no attachment param on the SMS send path). See ROADMAP.md's 6D entry before scoping it; needs
its own research pass, not a quick add-on.

Correction for future sessions: the `office` test role has no `conversations.*` permission (only owner/admin
do, by design) and cannot open Communications at all — use an owner/admin login for any Communications
browser check, not `office`. Raad LTD admin: jafarkhaninupwork@gmail.com / 11223344.

## Exact next action

Read `docs/communications-a2-implementation-plan.md` §7 in full plus the existing Automation action catalog
(find the typed action definitions and worker) to scope the smallest correct Send SMS action before coding.

## Constraint

A2P 10DLC cannot be completed for Jafar's test org; nothing actually sends. Provider-owned actions stay
Jafar's. Live delivery-tick states (delivered/failed) can't be produced end-to-end for the same reason.

Resume: `read memory and continue — communications-activation`.
