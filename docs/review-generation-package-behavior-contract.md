# Review Generation package

**Status:** Planning

## Summary

Jafar wants to sell a small "Review Generation" package to businesses that only want more Google reviews,
following Review Harvest. His working price is $50 a month. A business on this package sees only what asking
for reviews needs, not quotes, invoices, or the rest of the CRM. To allow that, the package builder stops forcing
the basics into every package: Jafar can untick them, and ticking a feature automatically ticks the features it
needs, so a package cannot break. The business brings its customers in, asks new customers for a review after
each service, and can ask its past customers once. The review asking already built for the Google review
campaign — texts and emails, reminders, the feedback page, private feedback, and the Reviews page — is reused,
not rebuilt. What ships first and what waits is still being decided.

## Choosing features in the package builder

Agreed with Jafar on 2026-10-07, following software installers and Salesforce CPQ's "Add" selection rule.

- The basics — Dashboard, Customers, Requests, Quotes, Jobs, Scheduling, Invoices, Team, and Customer access —
  start ticked in a new package, and Jafar can untick them.
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
- Once this plan is approved, these rules replace the "Every package includes …" rule in the
  [package builder plan](package-builder-behavior-contract.md).

## The Review Generation package

- It follows Review Harvest's standalone review tool, not Jobber's reviews add-on: a business can buy it without
  the rest of the CRM.
- It reuses the review asking in the [Google review plan](google-review-campaign-owner-brief.md) unchanged.
- Package copy never promises "5-star reviews only", and no customer is kept from the public Google review
  option, as the package builder plan already requires.

## Still unclear

**Package builder**

- Which basics can never be unticked — for example Customers, Team, or Dashboard?
- The full "needs" list. Known so far: Quotes needs Jobs; Website chat needs Shared inbox; the automatic review
  ask needs Jobs and Custom automations; Requests needs Quotes or Jobs; Customer access needs Quotes or
  Invoices. Not yet checked: Jobs and Scheduling, Invoices and online payments, Sales pipeline, Marketing email,
  and automation triggers.
- What a business sees when a feature is off, outside that feature's own page: the menu, dashboard cards, the
  customer page's tabs and timeline, the Create menu, search, automation triggers, notifications, and setup
  steps.
- Whether the existing rules for moving a customer to a smaller package (records kept, anything over a limit
  resolved first) are enough when the feature removed is a basic.

**The Review Generation package**

- What a reviews-only business sees in its menu. Suggested: Dashboard, Customers, Reviews, and Settings.
- How the app learns that a service is done for a business that does not use our Jobs: sending by hand, a
  spreadsheet upload, a simple "mark service done" without Jobs, Zapier, or direct connections to Jobber,
  Housecall Pro, QuickBooks, or Square.
- Asking past customers once: who is included, how many asks a day, skipping anyone asked in the last six
  months, opt-outs, and the consent rules for texting old customers.
- A monthly ask limit like Review Harvest's 50, 100, or 300, or no limit because texts come from the business's
  own Communication Balance.
- Getting started: texting waits until the business's registration is approved. Can it start with email
  meanwhile? Which setup steps does this package show?
- What ships first and what waits: Zapier, the Google Business Profile connection (real reviews, knowing who
  reviewed, AI replies), a website review widget, automatic social posts of 5-star reviews, and direct
  connections to other apps.
- The package's name. "Review generation" is the common industry term; Review Harvest calls the past-customer
  ask "Review Reactivation".

## Not doing

- Hiding the public Google review option from unhappy customers, or promising "5-star reviews only" — Google's
  review policy, the US FTC, and the UK CMA treat it as review gating (Jafar, 2026-09-30). Review Harvest says the
  same.

## Research

- [Review generation package research, 2026-10-07](research/review-generation-package-2026-10-07.md)
- [HighLevel review-request behavior](research/highlevel-review-request-behavior-2026-09-25.md)
