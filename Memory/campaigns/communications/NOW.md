# Communications: Current Checkpoint

## Goal

Build one secure Conversations experience across independently gated email, Website Chat, Meta, and Twilio channels.

## Current part

Part 9 cross-domain completion. All gates now met (2026-08-28). Campaign is complete pending Jafar's
sign-off to close and delete this folder.

## Exact next action

Ask Jafar to confirm closing the campaign. On confirmation: remove the `communications` row from
`Memory/INDEX.md` and delete `Memory/campaigns/communications/`. If he wants it kept open, the only
remaining track is the HTTP email-worker/Brevo transport (still a stub) — scope that as a new part.

## Blockers

None. The HTTP email-worker/Brevo transport is still a stub; the DB layer runs ahead of it. This has
been out of scope for every part so far. Linked CLI migration history remains divergent; do not repair
it here.

## Essential pointers

- ROADMAP.md — pending browser-verification list is now empty (all three Platform Owner screens drained
  this session).
- Part 9 integration gate: 42 Communications Vitest files / 252 tests green (unchanged).
- Browser pass 2026-08-28, all via localhost:5173 with a Platform Owner session, seeded through the
  Supabase MCP then cleaned up:
  - `/jafar/communications` MessageRecoveryQueue — queue lists stuck mail, history reveals with a
    skeleton, retry re-queues + refreshes, cancel toasts "allowance is back" + refreshes. PASS.
  - `/jafar/settings/cleanup` — closing-org row renders, delete-impact preview prefetches on hover (no
    skeleton), failed_partial receipt lists + Retry cleanup toasts "fully complete" + removes the row.
    PASS.
  - `/jafar/organizations/[id]` Website Chat authority — suspend seed showed Reason/Suspended by/Since
    panel + every widget flipped to Suspended badge + Restore button; release reverted to Available.
    Rotate-token dialog warns the installation code stops working. PASS.
- Residual immutable audit rows on `platform_owner_audit_events` from the verification actions
  (message_retried/cancelled, website_chat_suspension_engaged/released) — by design, cannot be deleted,
  harmless.

## Completion gate

Met. Part 9 security/integration gates pass and the pending browser-verification list was drained in
one pass.
