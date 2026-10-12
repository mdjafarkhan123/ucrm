# Home screen and Reports

**Status:** Planning — Jafar chose on 2026-10-12: one Home that fits each person; eight first reports; Reports
in every plan, owner chooses who sees them; charts decided by what contractors need, not by build size. The
whole plan awaits his approval. Roadmap Part 13 of `crm-launch-readiness`.

## Summary

When a contractor opens the CRM in the morning, Home answers three questions at a glance: what work is on today,
what needs my action, and how much money is owed. A Reports screen then lets the owner or bookkeeper look at any
period — what was invoiced, what was collected, who owes what, the tax to pay, the work done and the hours worked —
with totals that match the accountant download to the cent. We follow Jobber: its Home, its Insights charts and
its core reports, which every Jobber plan includes.

## Problem and audience

Today the landing page shows counts of customers, properties and requests, and nothing about money or the day's
work. The only report is the accountant CSV hidden in Invoice settings. An owner who wants to know "who still owes
me money?" must open invoices one by one.

- **Owners, admins and finance** need money owed, revenue, cash collected, tax and the state of every stage of
  work.
- **Office staff** need today's schedule and what is waiting for action, with money only where allowed.
- **Field workers** need their own visits today and their hours, never prices.

## First version

1. One **Home** page, the place everyone lands, with cards shown only to people allowed to see them.
2. A **Reports** area in the sidebar with an **Insights** overview of charts and eight reports.
3. Every money figure follows `docs/financial-reconciliation-contract.md`, so Home, Reports, list pages and the
   accountant download agree.

## Home

The sidebar item and page title become **Home** (Jobber's name); the address stays `/dashboard` so saved links keep
working. The page header greets the person ("Good morning, Jafar"), shows today's date in the business's time
zone, and has a **New** menu (Client, Request, Quote, Job, Invoice — each only if the person may create it). The
inline add-customer, add-property and add-request forms on today's Dashboard are replaced by that menu.

Cards, top to bottom; any card the person may not see is left out entirely, never shown as zero:

1. **Day clock** — the existing clock in/out card, for people who track time.
2. **Setup guide** — the existing setup and readiness cards for owners and admins, until setup is complete.
3. **To do** — four columns, Requests, Quotes, Jobs and Invoices, following Jobber's workflow summary. Each line
   has a count and, where the person may see prices, a value; clicking a line opens that list already filtered.
   - Requests: New; Assessment completed.
   - Quotes: Approved (ready to become a Job); Changes requested; Draft.
   - Jobs: Requires invoicing; Action required (open, with no upcoming Visit).
   - Invoices: Draft; Awaiting payment; Past due.
   - A line with nothing in it shows a quiet "None"; a column whose list the person cannot open is left out.
4. **Today's schedule** — Visits, Assessments and Tasks for today in time order, with tallies: Overdue (end time
   passed, not complete), In progress, Still to do, Completed. A toggle switches between **By visit** and **By
   person** (each teammate's items and logged time). The day's work value appears only to people who can see Job
   prices; deposits, discounts and tax are left out of it, as in Jobber. A field worker sees only their own items
   (their existing "assigned" access) and their hours today and this week.
5. **Money owed** — total owed, how many clients owe, and the three clients most overdue with amount and days
   late; "View all" opens the Money owed report. Requires Invoice price visibility.
6. **Business performance** — three figures, each compared with the previous period by an up or down arrow:
   - **Upcoming work:** value of Visits scheduled this week (Monday to Sunday) vs last week.
   - **Invoiced this month:** billed sales before tax, vs last month to the same day.
   - **Collected this month:** cash received less refunds, vs last month to the same day.

A brand-new business sees the setup guide and friendly empty cards ("No invoices yet — your first invoice will
show here"), never a wall of zeros. On a phone the cards stack in the same order; the To do columns become one list
grouped by stage.

## Reports

A **Reports** item joins the sidebar for people with the Reports permission. The Reports area has two tabs:

- **Insights** — the overview with charts (below).
- **All reports** — the eight reports grouped as Money (Invoices, Payments received, Money owed, Client balances,
  Tax) and Work (Visits, Timesheets, Quotes), each with a one-line description.

### What every report has

- A date range with presets — Today, Yesterday, This week, Last week, Last 30 days, This month, Last month, This
  year, Last 12 months, Custom — counted in the business's time zone. Money owed and Client balances use a single
  "as of" date instead.
- Overview tiles at the top that act as filters when clicked (for example "Past due" on Invoices).
- Filters suited to the report, sortable columns, and a column picker.
- A totals row that always reflects every active filter (Jobber's totals ignore some filters; ours do not).
- **Download CSV** of all columns or only the visible ones, downloaded directly.
- Long reports load page by page; totals always cover the whole filtered range, not just the loaded page.
- Clicking a row opens the record (Invoice, Client, Visit, Quote).

### The eight reports

1. **Invoices** — every issued Invoice in the range. Choose which date the range uses: Issued, Due or Paid.
   Tiles: Awaiting payment, Past due, Paid, Bad debt. Columns: number, client, issued, due, status, amount before
   tax, tax, total, paid, balance. Drafts appear only when the Draft filter is chosen and never count as sales.
   Includes the weekly **Invoiced vs collected** chart, as Jobber's Invoices report does.
2. **Payments received** — every payment, deposit, refund and reversal by date: client, method, amount, tip, and
   what it was applied to. Totals: received, refunded, net cash. Tips are shown in their own column and are not
   sales.
3. **Money owed** — what each client owes as of a date, split by how late: Not yet due, 1–30, 31–60, 61–90 and
   over 90 days. Includes opening balances entered at setup.
4. **Client balances** — every client who owes money or holds unused credit: owed, credit, balance.
5. **Tax** — tax charged per tax rate, in two views as Jobber offers: **Invoiced** (by invoice date) and
   **Collected** (by payment date), with an "Unapplied money" line for payments not yet applied to an invoice.
6. **Visits** — Visits in the range: date, client, Job, assigned people, status, completed or not, value (with Job
   price visibility). Totals: number of Visits and value.
7. **Timesheets** — hours by person and by day or Job in the range, approved or not, and labor cost for people who
   can see costs. Follows each person's existing own/team time access.
8. **Quotes** — Quotes sent in the range: client, value, status, and days to approve. Tiles: Sent, Approved,
   Converted, Declined, with the approval rate (approved ÷ sent).

### Insights

Following Jobber's Insights page (included on its cheapest plan), with a period chooser — Month to date, Last
month, Year to date, Custom — and each figure compared with the same period last year. Each chart opens its
report.

- **Overview:** new requests, quotes approved, new Jobs, invoiced amount.
- **Revenue:** invoiced and collected per week or month (bar chart), and invoiced amount by lead source.
- **Cash flow:** money owed now, invoices due in the next 7 days, and average days to get paid.
- **Winning work:** quote approval rate and average days from sending to approval.
- **Upcoming work:** value of scheduled Visits over the next 14 days, 4 weeks or 4 months.
- **Profit:** Job revenue, costs and profit, shown only to people who can see costs.

A chart with too little data shows a short note ("Charts appear once you have a few weeks of invoices") instead of
an empty picture. Charts have a table view for screen readers and for exact numbers.

## Who sees what

- A new **Reports** permission controls the Reports item and the Insights tab. It is included in every plan. It is
  on by default for Owner, Admin and Finance, and the owner can switch it on for anyone else.
- Each report also needs that area's existing permissions: money reports need Invoice price visibility; Visits
  needs Job access, with values only for Job prices; Timesheets follows own/team time access; Quotes needs Quote
  access, with values only for Quote prices; Profit needs Job costs.
- Hidden money is left out, never shown as zero. A person who opens a report they cannot use sees a plain
  "You don't have access to this report" message.
- Home cards follow the same rules.

## Money rules

All figures follow `docs/financial-reconciliation-contract.md`:

- "Invoiced" means billed sales before tax; drafts, voided and replaced invoices are not counted.
- "Collected" means cash received less refunds; a reversed mistaken payment is removed.
- "Money owed" is the same figure on Home, the Invoices page, the Money owed report and Client balances, and it
  includes opening balances. Today the Invoices page leaves opening balances out; that is corrected.
- Tips are recorded as payment facts so the Payments report and the accountant download can show them; they never
  count as sales.
- Days, weeks (Monday start) and months follow the business's time zone. The accountant download's default "last
  month" also changes to use the business's time zone instead of the viewer's computer.

## Success checks

- An owner with two past-due invoices opens Home → the Invoices column shows "Past due 2" with their total →
  clicking it opens the Invoices list showing exactly those two.
- A field worker opens Home → sees only their visits today and their hours; no money, no To do money values, no
  Reports item; opening `/reports` directly shows the no-access message.
- For any month, Invoiced, Collected, Money owed and Tax on Home, Insights and the reports equal the matching
  totals in the accountant download for the same period.
- A refund recorded today lowers Collected this month and the Payments report's net cash, but not Invoiced.
- A brand-new business sees the setup guide and empty-state messages, and no broken charts.
- A business in a time zone 12 hours away from the viewer's computer sees "today" as the business's today.

## Assumptions

- Weeks start on Monday until the week-start setting exists (roadmap Part 15, Jafar 2026-10-12); Home, Insights
  and reports then follow that setting.
- Jobber's exact Home card labels are inferred from its help pages and phone app; a signed-in Jobber tour has not
  confirmed them.

## Still unclear

- None blocking; awaiting Jafar's approval of the whole plan.

## Not doing

- Saved custom reports, scheduled report emails, revenue goals, AI report builder — Jobber's higher plans.
- Team productivity, salesperson, expense, re-engagement and delete-log reports — later, on demand.
- Revenue heatmap by postcode, bank payouts card — need map work or Stripe payout reconciliation first.
- A separate home page for non-admins — Jafar chose one page that fits each person.
- A week-start setting in this part — Jafar asked for it as a separate later item (roadmap Part 15).

## Sources and design decisions

- [Home and Reports research](research/home-and-reports-2026-10-12.md) — Jobber Home, Insights, reports, access
  and edge cases; our existing data and gaps.
- [Financial reconciliation contract](financial-reconciliation-contract.md) — the meaning of every money figure.
- Design: to be drawn in `classic.pen` below the Classic design system, at 1440px and 390px, after approval.
