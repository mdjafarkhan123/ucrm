# Assigned-only members still pay per-row permission checks

- **Priority:** P3
- **Status:** Full-access members fixed 2026-09-28 (Part 11 of deferred-launch-sweep, migrations
  `20260929150000` and `20260929160000`): timeline, notes, attachments, tags, client contacts, invoice
  history, schedule events now check permissions once per query. Owner's whole timeline 508 → 7 ms.
- **What's left:** a member who sees only assigned work (field crew) still falls through to
  `private.can_view_linked_entity` per row — about 1 ms per row (field worker's whole timeline ~790 ms;
  one record's timeline ~20–30 ms). `property_contacts`, `property_contact_methods`, and
  `request_pricing_lines` still call their per-row helpers for everyone.
- **Reactivate when:** field-crew record pages feel slow, or those tables' policies change.
- **Constraint:** preserve assigned-work visibility; prove it by fingerprinting each role's visible rows
  before and after (same method as Part 11).
