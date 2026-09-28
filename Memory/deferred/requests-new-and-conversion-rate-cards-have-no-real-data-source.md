# Requests list's "New requests" and "Conversion rate" cards have no real data source

- **Priority:** P2
- **Found:** 2026-09-28, incidentally, while fixing the Requests page's third KPI card
  ("No fake numbers", deferred-launch-sweep Part 3). Not on that part's original task list.
- **What is wrong:** on `/requests`, the "New requests" and "Conversion rate" `KpiCard`s in
  `src/routes/(app)/requests/+page.svelte` both hard-code `value="—"` — same unwired-placeholder shape the
  third card had, just never flagged. Jobber's own Requests list shows these two with a real trailing-30-day
  count/trend and a real conversion percentage (`.claude/skills/jobber/jobber-02-requests-leads.md` §4.1).
- **Reactivate when:** the launch-completeness pass, or any further Requests list work.
- **Constraint:** "New requests" needs a past-30-days count with a trend vs. the prior 30 days; "Conversion
  rate" needs a requests-that-became-quotes-or-jobs ratio over the same window. Neither has a query yet.
- **Pointers:** `src/routes/(app)/requests/+page.svelte`.
