---
name: automation-6d2-action-park-assertions-are-stale
description: automation_6d2_claims_and_recovery.sql still asserts the pre-6D-3 action park, so 5 of its 34 assertions fail
metadata:
  type: project
---

`supabase/tests/database/automation_6d2_claims_and_recovery.sql` still describes the behaviour
`advance_automation_work_item` had before 6D-3 gave `action` steps a real adapter: it expects
`action_not_available` and a `needs_attention:action_not_available` park, then resumes that parked row.
Since 6D-3 the function returns `action_due` and leaves the row claimed, so those assertions and the
`resume_automation_work_items` case built on them fail (5 of 34 on 2026-08-31). One of the five may
instead be the shared-remote `intake_automation_events(25) = 0` assertion, which any other tenant's
pending event can break. Not a product defect — the engine behaves as 6D-3/6F-1 intend and its own
suites are green.

6F-1 already repaired this file's fixtures (its enrollments now point at real `awaiting_response`
quotes, which the transition rechecks); only the park block is stale.

**Reactivation trigger:** the next Automation slice that touches the worker claim/recovery path, or
any run that needs this suite green.
