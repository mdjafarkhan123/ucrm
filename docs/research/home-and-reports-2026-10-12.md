# Home screen and Reports: research, 2026-10-12

Evidence for roadmap Part 13 (`Memory/campaigns/crm-launch-readiness/ROADMAP.md`). Jobber facts come from its help
centre, pricing page and changelog, read 2026-10-12; no signed-in tour was possible, so items marked
**unverified** need one. Our-app facts were checked against the code on 2026-10-12.

## Jobber Home (web, admins)

Source: [Home](https://help.getjobber.com/en/articles/home/) (updated 2026-02-05). In order:

1. **Setup guide** — "Business essentials", "Personalizing", "Client experience"; disappears when done.
2. **Today's appointments** — visits, assessments and tasks; Visit / Employee toggle; header dollar values for
   Total, Active, Completed, Overdue, Remaining. Overdue = end time passed and not complete; Active = now inside the
   window. One-off job value counts on its final visit; recurring per-visit jobs count that visit's items;
   deposits, discounts and taxes excluded. Employee view shows each person's logged time.
3. **Jobber Payments** — money on its way to the bank, instant-payout funds.
4. **Reminders** — shown only when present; today only "recurring jobs ending within 30 days".
5. **Business performance** — Receivables (total, number of clients, top 3 overdue clients with days late; "View
   all" opens Client balance summary); Upcoming jobs (this week's value vs last week); Revenue (sent invoices this
   month, after discount, before tax).

Workflow summaries (Requests, Quotes, Jobs, Invoices with count and value per status) were restored 2024-10-03
([changelog](https://productupdates.getjobber.com/page/10)); exact labels and position **unverified**. Likely
statuses, from the phone To Do list: Requests New / Assessment completed; Quotes Changes requested / Approved;
Jobs Requires invoicing / Action required (no upcoming visit); Invoices Draft / Awaiting payment / Past due.

Non-admins get a separate "Dashboard" ([source](https://help.getjobber.com/hc/en-us/articles/360033835353),
2026-08-06), filtered by permission: recommended actions (overdue or unassigned scheduled items, requests to
review, quotes with changes, approved quotes to convert, jobs requiring invoicing and drafts to send — the last two
only at 5 or more), assignments, outstanding balances, past-due invoices, upcoming jobs (next 7 days, 8–14 days,
unscheduled), and today's hours (own hours without timesheet access).

Phone app ([source](https://help.getjobber.com/en/articles/home-in-the-jobber-app/)): map and "Up next" for
everyone; admins add the day's expected revenue, a To Do list and this week's Business Health. Reports are web only
([Reports Basics](https://help.getjobber.com/en/articles/reports-basics/)).

Home uses fixed windows (today, this week vs last, this month); date pickers live only on the Insights tab
([Insights](https://help.getjobber.com/es/articles/insights-dashboard/)), which adds charts: revenue, lead source,
cashflow, lead conversion, scheduled job value.

## Jobber Reports

[Reports Basics](https://help.getjobber.com/en/articles/reports-basics/) (2026-08-11):

- **Financial:** Invoices, Transactions list, Bad debt, Aged receivables, Taxation, Projected income, Client
  balance summary, Payments transactions and payouts.
- **Work:** Visits, One-off jobs, Recurring jobs, Requests, Checklists, Quotes, Products & services, GPS
  waypoints, Timesheets, Team productivity.
- **Client:** Client communications, Client re-engagement, Clients (lead source, conversion), Lead source.
- **Other:** Delete log.

Plans ([pricing](https://www.getjobber.com/pricing/)): Core includes Insights and Financial, Client and Work
reports; Connect adds Expense, Salesperson and Team productivity reports; Plus adds revenue goals and an AI
custom-report builder.

A report screen has an options box; preset ranges (Today, Yesterday, This week, Last week, Last 30 days, This
month, Last month, This year, Last 12 months, All time, Custom); on Invoices a choice of which date to filter by
(Created, Issued, Due, Paid); overview tiles that filter the list; per-report filters; a column picker; sortable
columns; totals; "Email CSV" of all or visible columns ([Invoices
report](https://help.getjobber.com/en/articles/invoices-report/)). Jobber's Invoices tiles react only to the
created-date filter — a known weakness. Only the Invoices report has a chart (issued vs paid by week).

Access ([permissions](https://help.getjobber.com/en/articles/user-permissions/)): admins, or anyone with the
Reports permission, and then only reports whose own permissions they hold (e.g. Invoices also needs Show pricing).

Edge cases: revenue means sent invoices after discount and before tax, not cash; Taxation has Accrual and Cash
views with "Unallocated revenue" for unapplied money ([source](https://help.getjobber.com/en/articles/taxation-report/));
drafts are excluded; bad debt is separate; tips are a separate column outside the invoice total; client balance
shows both owing and credit; small samples hidden (top team members need 3 or more users). ServiceTitan separates
sales by sold date from revenue by completion date and warns they differ
([source](https://help.servicetitan.com/docs/dashboard-business-metrics)).

## Our app today

- `/dashboard` is the landing page (`src/routes/+page.server.ts`, login redirect). It shows the day clock, the
  setup and readiness cards (owner/admin), and counts of customers, properties and open requests from
  `/api/crm/overview`, which returns every row unpaged and checks only membership. No money, no schedule.
- **Money figures already exist** as paired page/summary SQL readers behind the accountant export
  (`src/lib/server/exports/financial-export.ts`) and unused JSON APIs under `src/routes/api/reports/financial/*`:
  invoice sales, tax, payment events, allocations, deposits and credits, client aging (1–30/31–60/61–90/91+),
  job profitability, time entries, uninvoiced work, sales outcomes. Rules: `docs/financial-reconciliation-contract.md`.
- **Figures that can disagree today:** `invoice_money_overview` (Invoices page Outstanding/Overdue) excludes
  opening balances and invoices marked received, while client aging includes opening balances; "Collected this
  month" is gross of refunds while payment events' cash effect subtracts them. Tips are stored only on Stripe
  checkouts and are in no ledger.
- **Counts:** `/api/requests/counts` (checks membership only, not `requests.view`), `/api/quotes/counts` (no money
  per status), `/api/jobs/counts` (`requires_invoicing`, org-wide `visits_today`), `/api/invoices/counts`.
  Schedule: `/api/schedule/visits?from&to`, narrowed by row security for "assigned" scope. No "my day" endpoint.
- **Not available:** time-bucketed trends, quote value by status, expense totals, a chart library.
- **List pages ignore URL filters:** invoices, quotes, jobs and requests keep `status` in local state, so a Home
  card cannot yet open a filtered list. `/invoices/ready-to-bill` and `/pipeline/outcomes` can.
- **Permissions:** roles owner, admin, office, sales, field, finance; money keys `invoices.view_price`,
  `jobs.view_price`, `jobs.view_cost`, `quotes.view_price`, `pipeline.view_value`, `customers.view_financials`.
  Money SQL returns null without permission. No reports permission yet; `report.*` keys map to the planned,
  unsold feature `reporting.advanced` (`src/lib/server/access/effective.ts`).
- **Timezone:** `organization_settings.timezone`; `calendarDay`, `organizationDayRange`,
  `private.organization_today`. The accountant export's "last month" default uses the browser's zone.
- **Reusable parts:** `KpiCard`, `DataTable` (footer for totals), `FilterBar`, `EmptyState`, `ErrorState`,
  `LoadingSkeleton`, `StatusOverviewCard`, `CalendarPicker`, `SegmentedControl`, `Tabs`; closest report screen
  is `src/routes/(app)/pipeline/outcomes/+page.svelte`.
