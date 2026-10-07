# Package basics unlock

**Status:** Planning

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
- Once this plan is approved, these rules replace the "Every package includes …" rule in the
  [package builder plan](package-builder-behavior-contract.md).

## Unlocking the basics one at a time

Agreed with Jafar on 2026-10-07, following the rule extras already follow: a feature is sold only after its
screens, commands, background work, and access are verified.

- A basic can be unticked only after every screen has been checked without it. Until then it stays ticked and
  locked in the builder, with a short reason.
- Some basics stay in every package; which ones is still unclear.

## A business without a feature

- A business on a package without a feature sees no trace of it: no menu item, and no broken or empty part of
  any other page that belongs to it.

## Still unclear

- Which basics stay in every package. Suggested: Customers, Team, and Dashboard, because every business needs
  them.
- The full "needs" list. Known so far: Quotes needs Jobs; Website chat needs Shared inbox; the automatic review
  ask needs Jobs and Custom automations; Requests needs Quotes or Jobs; Customer access needs Quotes or
  Invoices. Not yet checked: Jobs and Scheduling, Invoices and online payments, Sales pipeline, Marketing email,
  and automation triggers.
- What a business sees, place by place, when a feature is off: the menu, dashboard cards, the customer page's
  tabs and timeline, the Create menu, search, automation triggers, notifications, setup steps, and the job
  choice in the review-request panel.
- Whether the existing rules for moving a customer to a smaller package (records kept, anything over a limit
  resolved first) are enough when the feature removed is a basic.

## Not doing

- The Review Generation package's own features — asking past customers in bulk, Zapier and other-app
  connections, the Google Business Profile connection, a review widget, social posts, and a monthly ask limit —
  wait for their own campaign (Jafar, 2026-10-07).
- Linking features both ways. Ticking Jobs never pulls in Quotes or Invoices; two-way groups would make the
  smaller packages this change exists for impossible.

## Research

- [Review generation package research, 2026-10-07](research/review-generation-package-2026-10-07.md) — Review
  Harvest, NiceJob, Jobber Reviews, how installers and Salesforce CPQ add what an item needs, and what UCRM has
  today.
