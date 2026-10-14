# Home screen and Reports

**Status:** First version approved by Jafar on 2026-10-12, including the six decisions settled after the fresh
review (Office sees money cards; Late follows the Schedule rule; tips separate from Collected; Money owed shows
today; "Mark received" invoices listed as Needs checking; two Tax views). Earlier the same day he chose one Home
that fits each person, eight first reports, and Reports in every plan with the owner choosing who sees them, and
asked that charts follow what contractors need, not build size. Next: design in `classic.pen`. Roadmap Part 13 of
`crm-launch-readiness`.

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
- **Office staff** need today's schedule and what is waiting for action. With the stock permissions Office can see
  invoice amounts (granted 2026-09-28), so Office also sees the money cards; an owner can switch that off per person.
- **Field workers** need their own visits today and their hours, never prices.

## First version

1. One **Home** page, the place everyone lands, with cards shown only to people allowed to see them.
2. A **Reports** area in the sidebar with an **Insights** overview of charts and eight reports.
3. Every money figure follows `docs/financial-reconciliation-contract.md`, so Home, Reports, list pages and the
   accountant download agree. The contract is amended as described under "Money rules".
4. The Requests, Quotes, Jobs and Invoices lists open already filtered when a link names a status, so Home and
   report tiles can send people straight to the right records.

## Home

The sidebar item and page title become **Home** (Jobber's name); the address stays `/dashboard` so saved links keep
working. The page header greets the person ("Good morning, Jafar"), shows today's date in the business's time
zone. New records are created from the top bar's **Add
new** menu, which every page already has, so Home has no second New button (Jafar approved the Home design that way
on 2026-10-14). The inline add-customer, add-property and add-request forms on today's Dashboard are removed.

Each card loads on its own with a placeholder shape while loading; if one card fails it shows its own "Couldn't
load — Try again" message and the rest of Home still works. Cards, top to bottom; a card the person may not see is
left out entirely, never shown as zero:

1. **Day clock** — the existing clock in/out card, beside the greeting, for people who track time.
2. **Setup guide** — the existing setup and readiness cards for owners and admins, until setup is complete.
3. **To do** — four columns, Requests, Quotes, Jobs and Invoices, following Jobber's workflow summary. Counts are
   for the whole business. Each line has a count and, where the person may see that area's prices, a value;
   clicking a line opens that list filtered to those records.
   - Requests: Needs approval (website bookings); New; Assessment complete.
   - Quotes: Approved (ready to become a Job); Changes requested; Draft. Value is the Quote total.
   - Jobs: Requires invoicing; Action required; Ending soon (recurring Jobs that end within 30 days — Jobber's
     Home reminder, added with the approved design on 2026-10-14). Value is the amount not yet invoiced; Ending
     soon shows a count only.
   - Invoices: Draft; Awaiting payment; Past due. Value is the balance still owed (Draft: its total).
   - A column appears only to people who can see every record in that area; someone who sees only work assigned
     to them (stock Field role) gets no To do card. A line with nothing in it shows a quiet "None".
4. **Today's schedule** — Visits, Assessments and Tasks for today in time order, using the same status rules as
   the Schedule screen so the two never disagree: **Completed**, **In progress** (someone's timer is running on
   it), **Still to do**, and a separate line **Late from earlier days** (not completed and its day has passed).
   A visit with no one assigned shows an **Assign** button that opens it to choose who goes, as Jobber flags
   unassigned visits. The header shows the day's count and value, how many items are done, in progress and still
   to do with their values, and small counts of late and unassigned items.
   Anytime items (a date but no time) are listed after timed ones. A toggle switches between **By visit** and **By
   person** (each teammate's items and logged time). The day's work value appears only to people who can see Job
   prices, using the Visit value rule below. A field worker sees only their own items and their hours today and
   this week.
5. **Money owed** — total owed (see Money rules), how many clients owe, the overdue part, and the three clients
   most overdue with amount and days late; "View all" opens the Money owed report.
6. **Business performance** — three figures, each compared with the previous period by an up or down arrow:
   - **Upcoming work:** value of Visits scheduled this week (Monday to Sunday) vs last week.
   - **Invoiced this month:** billed sales before tax, vs last month up to the same day (on the 31st, compared
     with the whole of a shorter last month).
   - **Collected this month:** cash collected, vs last month up to the same day.

A brand-new business sees the setup guide and friendly empty cards ("No invoices yet — your first invoice will
show here"), never a wall of zeros. On a phone the cards stack in the same order; the To do columns become one list
grouped by stage.

### Visit value

Following Jobber: a Job priced as one whole amount counts its value on its last Visit; a Job priced per Visit
counts that Visit's items; Jobs billed a fixed amount per period are left out of Visit value. Deposits, discounts
and tax are left out.

## Reports

A **Reports** item joins the sidebar for people with the Reports permission. The Reports area has two tabs:

- **Insights** — the overview with charts (below).
- **All reports** — the eight reports grouped as Money (Invoices, Payments received, Money owed, Client balances,
  Tax) and Work (Visits, Timesheets, Quotes), each with a one-line description.

### What every report has

- A date range with presets — Today, Yesterday, This week, Last week, Last 30 days, This month, Last month, This
  year, Last 12 months, Custom — counted in the business's time zone. Money owed and Client balances show today.
- Overview tiles at the top that act as filters when clicked (for example "Past due" on Invoices).
- Filters suited to the report, sortable columns, and a column picker.
- A totals row that always reflects every active filter (Jobber's totals ignore some filters; ours do not).
- **Download CSV** of all columns or only the visible ones, downloaded directly, covering the whole filtered range
  however long; if the download fails the person sees why and can retry.
- Long reports load page by page; totals always cover the whole filtered range, not just the loaded page.
- Clicking a row opens the record (Invoice, Client, Visit, Quote).
- States: loading placeholder rows; "Nothing in this period" with the range named when there are no rows; an error
  message with Try again.

### The eight reports

1. **Invoices** — every issued Invoice in the range. Choose which date the range uses: **Issued**, **Due** or
   **Paid** (the day the balance reached zero). Tiles: Awaiting payment, Past due, Paid, Bad debt. Columns:
   number, client, issued, due, paid, status, amount before tax, tax, total, paid amount, balance. Drafts appear
   only under the Draft filter; a Draft counts as a sale only once fully paid, as the contract says. Includes the
   weekly **Invoiced vs collected** chart, as Jobber's Invoices report does.
2. **Payments received** — every payment, deposit, refund and reversal by date: client, method, amount, tip, and
   what it was applied to. Totals: received, refunded, collected (received less refunds), and tips.
3. **Money owed** — what each client owes today, split by how late: Not yet due, 1–30, 31–60, 61–90 and over 90
   days. Opening balances are aged from their as-of date. Older invoices closed with the retired "Mark received"
   action are not counted as owed; they are listed in a "Needs checking" note under the table so the owner can
   record the real payment or bad debt.
4. **Client balances** — every client who owes money or holds unused credit: owed, credit, balance (owed less
   credit).
5. **Tax** — tax per tax name and rate, in two views as Jobber offers: **Invoiced** (by invoice date) and
   **Collected** (by payment date), with an "Unapplied money" line for money received but not applied to an
   invoice.
6. **Visits** — Visits in the range: date, client, Job, assigned people, status, value (Visit value rule, with Job
   price visibility). Totals: number of Visits and value.
7. **Timesheets** — hours by person and by day or Job in the range, approved or not, and labor cost for people who
   can see costs. Follows each person's existing own/team time access.
8. **Quotes** — Quotes first sent in the range: client, value, status, and days from sending to the customer's
   decision. Tiles: Sent, Approved, Converted, Declined, with the approval rate ((approved + converted) ÷ sent).

### Insights

Following Jobber's Insights page (included on its cheapest plan), with a period chooser — Month to date, Last
month, Year to date, Custom — and each figure compared with the same period last year. Each chart opens its
report. Each figure follows the same permission as its report and is left out for people who cannot see it.

- **Overview:** new requests, quotes approved, new Jobs, invoiced amount.
- **Revenue:** invoiced and collected per week or month (bar chart), and invoiced amount by client lead source
  (spelling differences grouped together, blanks shown as "Not set", the six largest shown and the rest as
  "Other").
- **Cash flow:** money owed now, invoices due in the next 7 days, and average days to get paid (issue date to the
  day the balance reached zero, for invoices fully paid in the period).
- **Winning work:** quote approval rate and average days from sending to approval.
- **Upcoming work:** value of scheduled Visits over the next 14 days, 4 weeks or 4 months.
- **Profit:** Job revenue, costs and profit, shown only to people who can see costs.

A chart with no data in the period shows "Nothing in this period yet" instead of an empty picture. Charts have a
table view for screen readers and for exact numbers.

## Who sees what

- A new **Reports** permission (`reports.view`) controls the Reports item and the Insights tab. It is included in
  every plan, so it is not part of the unsold "advanced reporting" feature. It is on by default for Owner, Admin
  and Finance, and the owner can switch it on for anyone else.
- Each report also needs that area's existing permissions: money reports need Invoice access with prices
  (`invoices.view` and `invoices.view_price`); Visits needs Job access, with values only for Job prices; Timesheets
  follows own/team time access; Quotes needs Quote access, with values only for Quote prices; Profit needs Job
  costs.
- Hidden money is left out, never shown as zero. A person who opens a report they cannot use sees a plain "You
  don't have access to this report" message.
- Home cards follow the same rules. Money owed and Business performance need Invoice access with prices.

## Money rules

All figures follow `docs/financial-reconciliation-contract.md`. This plan amended it on 2026-10-12 in four places:
its permission section is updated to the 2026-09-28 Finance and Office invoice access; it gains the cash-basis
tax rule and the tips rule below; and "Money owed" is defined below.

- **Invoiced** means billed sales before tax: issued invoices, plus Drafts once fully paid; voided and replaced
  invoices are not counted.
- **Collected** means cash received — payments and quote deposits — less refunds; a reversed mistaken payment is
  removed. Tips are not part of Collected; they are shown as their own figure.
- **Money owed** is clients' outstanding invoice balances plus opening balances owed, before credit. It is the
  same figure on Home, the Invoices and Jobs pages' overview, and the Money owed report. Client balances shows the
  same owed figure and subtracts unused credit. Today the Invoices and Jobs overview leaves opening balances out
  and the aging export counts "Mark received" invoices; both are corrected to this rule.
- **Tax collected** (cash basis) is the tax share of each payment applied to an invoice: payment applied × invoice
  tax ÷ invoice total, on the payment date. The accountant download gains a matching cash-basis tax file.
- **Tips** become a recorded part of each payment, including past card payments, so the Payments report and the
  accountant download show them. They never count as sales or as Collected.
- Days, weeks (Monday start) and months follow the business's time zone. The accountant download's default "last
  month" also changes to use the business's time zone instead of the viewer's computer.

## Success checks

- An owner with two past-due invoices opens Home → the Invoices column shows "Past due 2" with their balance →
  clicking it opens the Invoices list showing exactly those two.
- A field worker opens Home → sees only their visits today and their hours; no To do card, no money, no Reports
  item; opening `/reports` directly shows the no-access message.
- For any month, Invoiced, Collected, Money owed and both Tax views on Home, Insights and the reports equal the
  matching totals in the accountant download for the same period.
- A refund recorded today lowers Collected this month and the Payments report's collected total, but not Invoiced.
- A $20 tip on a card payment shows in the Payments report's tips total and the download, and changes neither
  Invoiced nor Collected.
- A visit with a running timer shows as In progress on Home; a visit from yesterday not completed shows under Late
  from earlier days on Home and as Late on the Schedule.
- A brand-new business sees the setup guide and empty-state messages, and no broken charts.
- A business in a time zone 12 hours away from the viewer's computer sees "today" as the business's today.

## Assumptions

- Weeks start on Monday until the week-start setting exists (roadmap Part 15, Jafar 2026-10-12); Home, Insights
  and reports then follow that setting.
- Jobber's exact Home card labels are inferred from its help pages and phone app; a signed-in Jobber tour has not
  confirmed them.

## Still unclear

- None for the first version.

## Not doing

- Money owed as of a past date — the first version shows today, like Jobber's aged receivables.
- Saved custom reports, scheduled report emails, revenue goals, AI report builder — Jobber's higher plans.
- Team productivity, salesperson, expense, re-engagement and delete-log reports — later, on demand.
- Revenue heatmap by postcode, bank payouts card — need map work or Stripe payout reconciliation first.
- A separate home page for non-admins — Jafar chose one page that fits each person.
- A week-start setting in this part — Jafar asked for it as a separate later item (roadmap Part 15).

## Sources and design decisions

- [Home and Reports research](research/home-and-reports-2026-10-12.md) — Jobber Home, Insights, reports, access
  and edge cases; our existing data and gaps.
- [Financial reconciliation contract](financial-reconciliation-contract.md) — the meaning of every money figure.
- Visit status rule: `src/lib/schedule/status.ts` — Home's schedule follows it.
- Design: to be drawn in `classic.pen` below the Classic design system, at 1440px and 390px, after approval.
