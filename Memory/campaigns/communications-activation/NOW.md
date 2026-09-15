# Communications Activation: Current Checkpoint

## Goal

Make Communications deliver email and SMS through a GHL-style unified inbox and provide safe delivery channels
to dependent products such as Marketing. Email is live; SMS Stages 1–6 done. Everything stays dark (no live
traffic) until a country launch gate passes.

## Active part

**Stage 7 — SMS in Automation.** Core build done and applied to the remote database this session (uncommitted
in git — see below). "Send SMS" is a real, enabled action: catalog entry, recipe builder editor (body +
variable picker + live segment/cost estimate + optional sender pin), the shared SQL send engine
(`communication_sms_enqueue_operational` split into a private core + human/system wrappers,
`enqueue_automation_quote_sms`, `perform_automation_sms_effect`), and the worker (`advance_automation_work_item`
now returns `action_due_email` / `action_due_sms` instead of one `action_due`). Migration:
`supabase/migrations/20260919190000_automation_sms_effect.sql`, applied. Sender continuity (prefer the number
this customer's SMS has been using, else org default) mirrors Stage 6B's recipient-continuity pattern. Fixed a
pre-existing `max_messages` email-only counting bug in the activation-preview route while touching it.

**Known, deliberate gaps in this slice** (documented in the migration's header):
- SMS body variables are `customer_name` / `business_name` / `quote_number` only — **no `{{quote_link}}`**.
  The SMS send path mints no customer access link yet; that needs its own design pass because
  `quote_recipients`/`quote_access_links` are an email-shaped table (NOT NULL, email-format-checked email
  column) that would need to learn to represent a phone recipient.
- "Send a test to my verified team phone" — Jafar deferred this 2026-09-15; there is no phone-verification
  mechanism anywhere in the app yet (would likely mean a new Twilio product, e.g. Verify).
- Compliance/opt-out wording: the org's configured opt-out text (`communication_sms_compliance_settings`) is
  **not actually appended to any outbound SMS today** — Automation or Manual. Pre-existing gap, not introduced
  by Stage 7; flagged to Jafar, not fixed here since it would change already-shipped Conversations behavior.

**Not yet done for full Gate closure:**
- No browser/Playwright coverage added this session (unit tests + `npm run check` + a clean migration apply
  + advisor check all pass).
- Whether `stop.customer_reply` and other existing generic stop conditions behave correctly for an SMS
  enrollment was not independently re-verified (they're channel-agnostic by construction, inherited from Stage
  6F-1, but not re-tested here).
- **Nothing is committed to git yet** — all Stage 7 file changes are working-tree only. Review and commit before
  moving on.

Deferred, not blocking: **6D MMS** (pictures in Conversations) — genuinely unbuilt on both sides. See
ROADMAP.md's 6D entry before scoping it.

Correction for future sessions: the `office` test role has no `conversations.*` permission (only owner/admin
do, by design) and cannot open Communications at all — use an owner/admin login for any Communications
browser check, not `office`. Raad LTD admin: jafarkhaninupwork@gmail.com / 11223344.

## Exact next action

Review the uncommitted Stage 7 working tree with Jafar, commit it, then decide: browser-test this stage now,
or move to Stage 8 (billing reconciliation, recovery, launch proof) and fold Stage 7 browser coverage into
that stage's live-proof pass.

## Constraint

A2P 10DLC cannot be completed for Jafar's test org; nothing actually sends. Provider-owned actions stay
Jafar's. Live delivery-tick states (delivered/failed) can't be produced end-to-end for the same reason — this
also means Stage 7's "real charged test send" behavior cannot be proven live yet either.

Resume: `read memory and continue — communications-activation`.
