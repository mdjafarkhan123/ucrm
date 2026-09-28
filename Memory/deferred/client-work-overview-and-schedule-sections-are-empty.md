# Client page's Work overview and Client schedule sections are always empty

- **Priority:** P2
- **Fixed 2026-09-28:** the header's Lifetime/Open quotes/Active jobs stats (`ClientDetailHeader.svelte`) were
  the empty-for-everyone part of this note and are now wired to `public.client_work_summary`, gated on
  `customers.view_financials` / `quotes.view` / `jobs.view`. That part is closed.
- **What is still wrong:** on a client's Details tab, the "Work overview" and "Client schedule" `SectionBlock`s
  in `src/routes/(app)/clients/[id=uuid]/+page.svelte` are hard-coded `EmptyState`s ("No work yet" /
  "Nothing booked") regardless of whether the client actually has requests, quotes, jobs, invoices, or
  upcoming visits.
- **Reactivate when:** Jafar wants the client page's work history and upcoming schedule built. Explicitly
  deferred rather than folded into the "No fake numbers" sweep (Jafar, 2026-09-28) because it is a real build
  (a client work-records table plus an upcoming-visits feed), not a money/count rollup.
- **Constraint:** Jobber's own client page pattern (`.claude/skills/jobber/jobber-08-screen-patterns.md`,
  "The client's linked-work table") is one table of the client's own Request/Quote/Job/Invoice rows —
  type icon, title, property, created date, status badge, money right-aligned. Build "Work overview" against
  that shape rather than inventing a new one. "Client schedule" needs the visit/reminder schedule data Job
  Visits work already produces.
- **Pointers:** `src/routes/(app)/clients/[id=uuid]/+page.svelte` (SectionBlock title="Work overview" /
  title="Client schedule").
