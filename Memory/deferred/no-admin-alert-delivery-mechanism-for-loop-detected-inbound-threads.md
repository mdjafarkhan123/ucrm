# No admin-alert delivery mechanism for loop-detected inbound threads

`docs/contractor-email-contract.md` requires a detected inbound email loop to "pause the thread and alert
an administrator." No notification/alert delivery system exists anywhere in this codebase (checked during
Communications Part 4 item-4 design, 2026-08-25).

Communications Part 4 will mark a loop-detected inbound message DB-only
(`communication_inbound_messages.message_kind='loop_detected'`, `automation_suppressed=true`,
`loop_detected_at`) — auditable and visible once Part 5's inbox UI exists, but nothing actually pings an
administrator yet.

**Reactivation trigger:** once any in-app or email/push notification system is built for administrators
(for any reason — this need not be communications-specific), wire loop-detected threads into it.

**Priority:** P2 — real gap, but the DB-side marking already satisfies "auditable," and no loop has ever
occurred since inbound ingestion doesn't exist yet either.
