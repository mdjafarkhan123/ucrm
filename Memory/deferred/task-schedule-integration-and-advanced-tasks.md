# Task Schedule integration and advanced Tasks

- **Priority:** P2


- **Campaign:** `sales-pipeline` Part 3; implementation belongs to the future Schedule domain.
- **Reason:** Part 3 needs lightweight follow-up Tasks, but no Schedule route or unified scheduled-items feed
  exists. Building repeating/timed scheduling, reminders, notifications, or a placeholder calendar now would
  create the wrong ownership boundary.
- **Reactivation trigger:** The Schedule campaign begins or Jafar explicitly asks to schedule Tasks.
- **Prerequisites:** Part 3A's reusable Task foundation exists; Schedule defines how Tasks, Visits,
  Assessments, Events, and reminders share one feed without pretending they are the same object.
- **Pointer:** `docs/sales-pipeline-behavior-contract.md` and `docs/PRODUCT.md` §14.

