# Real (time-tracking) `Labor` block on the Request detail page

- **Priority:** P2


- **Campaign:** `quotes` Part 2, redefined 2026-08-20 (was "`Product & Services` and `Labor` blocks", closed
  `requests-and-assessments` 2026-08-18 entry).
- **Reason:** `Design/Request Details.jpg` draws a separate Labor block, and Part 2 originally built one that
  let staff type Labor lines by hand. Jafar caught live on 2026-08-20 that this doesn't match Jobber: a real
  Jobber Request's Labor section is read-only, auto-filled from time tracking, never typed — a feature this
  app does not have. The typed Labor block was removed entirely.
  **"Products and services" is shipped and out of this deferral now** — only the real, read-only,
  time-tracking-backed Labor block remains deferred. Until then, a crew's time is priced as a plain Service
  line inside "Products and services," matching what Jobber's own quotes show.
- **Reactivation trigger:** A Schedule/time-tracking domain exists and can supply hours worked against a
  Request.
- **Prerequisites:** Time tracking must exist first; this block reads from it, it does not create it.
- **Checkpoint:** `Design/Request Details.jpg`, `Design/Request new.jpg` (draw the block),
  `.claude/skills/jobber/jobber-02-requests-leads.md` §4.2 (Jobber's read-only Labor behavior).

