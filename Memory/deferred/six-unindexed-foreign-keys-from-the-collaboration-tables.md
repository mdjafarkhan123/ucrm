# Six unindexed foreign keys from the collaboration tables

- **Priority:** P2


- **Campaign:** `clients-properties` Part 3, deferred by explicit decision, restated on 2026-08-17.
- **Reason:** Row counts are tiny, so the planner scans them fine today.
- **What is missing:** Six Part 3 foreign keys have no covering index; `attachments.note_id` matters most
  because deleting a note has to find its attachments.
- **Reactivation trigger:** Any collaboration table passes a few thousand rows, or note deletion gets slow.
- **Prerequisites:** Confirm the missing indexes against `get_advisors` before writing the migration.
- **Checkpoint:** `20260816090000_client_property_data_model.sql`.
- `tasks.created_by` and `tasks.completed_by` (added 2026-08-19) take the same accepted trade-off: both point
  at `auth.users` and only matter when an account is deleted. `tasks.assignee_user_id`, which the product
  actually queries by, is indexed.

