# Unlocking package basics — research

**Researched:** 2026-10-07
**Scope:** What each basic needs, where a business would still see a feature its package leaves out, and how
mature products treat a business that loses a feature it already used. Code read on `main` and the live
feature list; public help pages only for other products.

## Short answer

- Most "needs" are already clear from how the records connect. Two are new: Jobs needs Scheduling (a job's
  visits live on the calendar), and Scheduling needs Jobs or Requests (nothing else puts work on it).
- Today the app hides a feature mainly by role permissions, not by the package. Several places would still
  show a missing basic: the menu, the client page summary, the dashboard's Requests panel, six Settings
  pages, and the automation triggers.
- Mature products keep the business's records when a feature is lost, turn off automations that depend on it,
  and keep things the business's own customers already received working.

## What each feature needs

From the code and the live feature list (`package_capability_requirements` holds only Website chat → Shared
inbox today).

| Feature | Needs | Why |
| --- | --- | --- |
| Quotes | Jobs | An approved quote becomes a job |
| Requests | Quotes or Jobs | A request converts to a quote or a job |
| Customer access | Quotes or Invoices | The customer portal shows quotes to approve and invoices to pay |
| Jobs | Scheduling | A job's visits are booked on the calendar (`jobs.schedule`) |
| Scheduling | Jobs or Requests | The calendar shows job visits and request assessments; nothing else |
| Sales pipeline | Requests or Quotes | Cards are made only from requests and quotes |
| Website chat | Shared inbox | Already enforced |
| Invoices and payments | — | An invoice can exist without a job; online payment is part of the same feature |
| Marketing email, Review requests | Customers | Customers are always included if they stay a must-keep |
| Custom automations | — | Each trigger appears only when its feature is in the package (see below) |

The automatic review ask is an Automations recipe on "A job's work is completed", so it appears only when Jobs
and Custom automations are both in the package; a manual ask needs only Customers.

## Where a missing basic still shows today

- **Menu** (`src/lib/components/layout/AppShell.svelte`): Dashboard, Schedule, Requests, and Jobs always show.
  Clients, Quotes, and Invoices show until a background check says no, so they would flash and vanish.
- **Client page header** (`src/lib/components/clients/ClientDetailHeader.svelte`): "Open quotes" and "Active
  jobs" read "You do not have access to quotes/jobs".
- **Dashboard** (`src/routes/(app)/dashboard/+page.svelte`, `/api/crm/overview`): a Requests panel and add form
  with no package check.
- **Settings** (`src/routes/api/settings/+server.ts`): Quote, Invoice, Payment, Tax, Price book, Checklist,
  and Form settings use `settings.*` permissions that belong to no feature, so they always show.
- **Other unlinked permissions**: `time.*`, `expenses.*`, `field_records.*` belong to jobs but are not tied to
  the Jobs feature (`permissionFeaturePrefixes` in `src/lib/server/access/effective.ts`).
- **Automations** (`src/lib/automation/catalog.ts`): quote and job triggers are offered whatever the package.
- **Already package-aware:** search (`/api/search`), Client setup stages, Marketing, Reviews, Shared inbox,
  Pipeline.

## Losing a feature already used

- **HubSpot:** workflows "are turned off" on downgrade, deleted after 90 days unless the customer upgrades back;
  published blog posts "stay live"; custom object records become read-only.
  [HubSpot: downgrade a paid subscription](https://knowledge.hubspot.com/account-management/downgrade-a-paid-subscription)
- **Zoho Invoice:** after a downgrade "existing data will remain in read-only mode".
  [Zoho Invoice: downgrade](https://www.zoho.com/invoice/kb/subscription/downgrade-existing-plan.html)
- **Jobber, Housecall Pro:** public help says only that a downgrade starts at the end of the billing cycle;
  what happens to the business's existing items is not documented publicly.
- **UCRM today:** before a smaller edition starts, Jafar resolves active resources above its limits; records
  and history remain (`docs/package-builder-behavior-contract.md`). Nothing covers open items of a removed
  basic, such as an unpaid invoice whose pay link the customer already has, or visits booked next week.
