# Package basics unlock

**Status:** Approved by Jafar on 2026-10-07

## Summary

Today every package includes nine basics, and the package builder does not let Jafar untick them. This change
lets Jafar build smaller packages, such as a reviews-only package, by unticking the basics a package does not
need. Ticking a feature automatically ticks what it needs, unticking asks first, and publishing still refuses a
broken package, so a business can never end up with a feature that cannot work. A business on a smaller package
sees no trace of the features it does not have. Basics become untickable one at a time, each only after every
screen has been checked without it. This change builds that ability only; the Review Generation package itself,
modeled on Review Harvest, is later work.

## Choosing features in the package builder

Agreed with Jafar on 2026-10-07, following software installers and Salesforce CPQ's "Add" selection rule.

- The basics — Dashboard, Customers, Requests, Quotes, Jobs, Scheduling, Invoices, Team, and Customer access —
  start ticked in a new package. Jafar can untick a basic once it is ready to be left out.
- A feature lists what it needs, and the link runs one way. Ticking a feature also ticks what it needs; it never
  ticks features that only work alongside it. For example, Quotes needs Jobs because an approved quote becomes a
  job: ticking Quotes ticks Jobs, but ticking Jobs leaves Quotes and Invoices off.
- Every automatic tick shows a note saying what was added and why, such as "Jobs added — Quotes needs it."
  Nothing joins a package without Jafar seeing it.
- Unticking a feature that another ticked feature needs asks first, for example "Quotes needs Jobs. Remove
  Quotes too?" with **Remove both** and **Keep Jobs**. Nothing is removed without Jafar choosing.
- When a feature needs either of two features and neither is ticked, the builder asks Jafar which one to add.
  It never guesses.
- Publishing still refuses a package whose needs are not met, as a last safety net.
- These rules replace the old "Every package includes …" rule in the
  [package builder plan](package-builder-behavior-contract.md).

## Unlocking the basics one at a time

Agreed with Jafar on 2026-10-07, following the rule extras already follow: a feature is sold only after its
screens, commands, background work, and access are verified.

- A basic can be unticked only after every screen has been checked without it. Until then it stays ticked and
  locked in the builder, with a short reason.
- Customers, Team, and Dashboard stay in every package and can never be unticked, because every business needs
  a customer list, a way to add staff, and a home screen (Jafar, 2026-10-07). Requests, Quotes, Jobs,
  Scheduling, Invoices, and Customer access can be unticked once each is ready.

## What each feature needs

Agreed with Jafar on 2026-10-07, from how the records connect.

| Feature | Needs |
| --- | --- |
| Quotes | Jobs — an approved quote becomes a job |
| Requests | Quotes or Jobs — a request becomes one or the other |
| Customer access | Quotes or Invoices — customers approve quotes and pay invoices there |
| Jobs | Scheduling — a job's visits are booked on the calendar |
| Scheduling | Jobs or Requests — nothing else puts work on the calendar |
| Sales pipeline | Requests or Quotes — its cards come only from these |
| Website chat | Shared inbox |

Invoices, Marketing email, Review requests, and Custom automations need nothing beyond the always-kept basics.
The automatic review ask is an automation that runs when a job's work is completed, so it is offered only when
Jobs and Custom automations are both in the package; asking by hand needs only Customers.

## A business without a feature

- A business on a package without a feature sees no trace of it: no menu item, and no broken or empty part of
  any other page that belongs to it.
- This covers every place, decided by the package and not only by the person's role (Jafar, 2026-10-07): the
  menu (no flash of an item that then disappears), dashboard boxes, the customer page's summary numbers and
  tabs, the Create menu, search, Settings pages for that feature (such as Quote, Invoice, Payment, Tax, and
  Price book settings), automation triggers and steps, notifications, setup steps, and the job choice in the
  review-request panel. A business never reads "You do not have access" about something its package leaves
  out.

## Moving a business to a smaller package

Agreed with Jafar on 2026-10-07, following HubSpot: records are kept, automations that rely on a removed
feature are turned off, and what customers already received keeps working.

- Before Jafar confirms the move, the preview lists the open items of every feature being removed: unpaid
  invoices, quotes awaiting a decision, upcoming visits, and automations that use the feature. He confirms with
  that list in front of him. The existing rule still applies: anything above the new package's limits is
  resolved first.
- After the move, those records are kept but hidden from the business. They come back unchanged if the
  business moves to a package with the feature again.
- Automations that rely on a removed feature pause and do not run.
- Links the business's customers already have, such as an invoice pay link, keep working, so the business can
  still be paid for work already done.

## Still unclear

- Nothing.

## Not doing

- The Review Generation package's own features — asking past customers in bulk, Zapier and other-app
  connections, the Google Business Profile connection, a review widget, social posts, and a monthly ask limit —
  wait for their own campaign (Jafar, 2026-10-07).
- Linking features both ways. Ticking Jobs never pulls in Quotes or Invoices; two-way groups would make the
  smaller packages this change exists for impossible.

## Research

- [Unlocking package basics research, 2026-10-07](research/package-basics-unlock-2026-10-07.md) — what each
  feature needs, where a missing feature still shows today, and how HubSpot and Zoho handle a lost feature.
- [Review generation package research, 2026-10-07](research/review-generation-package-2026-10-07.md) — Review
  Harvest, NiceJob, Jobber Reviews, how installers and Salesforce CPQ add what an item needs, and what UCRM has
  today.
