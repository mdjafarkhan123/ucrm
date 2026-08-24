# Two unindexed foreign keys on the invitations table

- **Priority:** P3


- **Campaign:** `contractor-settings`, found during item 3's performance review, 2026-08-27.
- **Reason:** `organization_member_invitations.invited_by` and `.cancelled_by` both point at `auth.users`
  with no covering index. No query reads by either column, so nothing is slow today - the cost lands on the
  parent side, where deleting an Auth user (organization purge) seq-scans the whole invitations table per
  row deleted. Same INFO-level pattern as the collaboration entry above and 34 other foreign keys app-wide.
- **Reactivation trigger:** organization purge is exercised against an organization with real invitation
  history, or the app-wide unindexed-foreign-key sweep is picked up.
- **Prerequisites:** none - two partial indexes (`where invited_by is not null` and
  `where cancelled_by is not null`) settle it, matching the shape already used for `invited_user_id`.
- **Checkpoint:** `mcp__supabase__get_advisors` type `performance`, lint `unindexed_foreign_keys`.

