# Opportunity Brief activity timeline

- **Priority:** P2


- **Campaign:** `sales-pipeline` Part 3, deferred by Jafar 2026-08-19.
- **Reason:** Jobber's current Opportunity Brief has Tasks and Notes but no embedded activity timeline. UCRM's
  existing `activity_events` omit important Request, Assessment, Opportunity-detail, Task, and Note mutations,
  so rendering them as full Opportunity history would be misleading.
- **Reactivation trigger:** Jafar asks for history inside the Brief, or the shared activity domain gains a
  complete event vocabulary for Request/Quote commercial work.
- **Prerequisites:** Define the event catalog, retention, pagination, permission/value-redaction rules, and
  whether the view merges Client history or only the backing Request/Quote.
- **Checkpoint:** `docs/sales-pipeline-behavior-contract.md`, `src/lib/components/collaboration/ActivityFeed.svelte`,
  `public.activity_events`, and `public.opportunity_stage_events`.

