# Package builder

**Status:** Planning — resumed on 2026-09-29. The direction below is confirmed; the complete behavior and implementation plan are not approved yet.

## Summary

Jafar builds packages in the Jafar workspace by choosing supported capabilities and tuning their settings and limits, like selecting items from a storeroom. He expects to offer two packages initially; this is not a requested two-package ceiling. Each customer receives a particular published edition, including its features, limits, and price. Editing the offer creates a new edition. Existing customers keep their assigned edition until Jafar manually assigns a newer one. The application currently has only fake organizations and test data, so preserving real customer contracts during replacement is unnecessary.

## Building packages

The builder lets Jafar select supported application capabilities and tune their configuration. Every package includes customers, requests, quotes, jobs, invoices, and payment recording. Optional capabilities, dependencies, and tuning controls remain to be planned. Packages can be public offers or private negotiated offers. The current implementation must not constrain the new product design to Starter, Growth, and Elite.

## Pricing

Approved 2026-09-29: packages have independently set monthly and yearly prices in USD only. Yearly means one upfront payment for the year.

Introductory offers support percentage or fixed-amount discounts, three/six-month presets and custom duration, and separate first-year offers for yearly customers. Controls include eligible packages and billing intervals, customer eligibility, claim dates, redemption caps, and optional promotion codes or automatic application. Only one promotion applies at a time. Show the introductory price, duration, and subsequent normal price clearly. Preserve the customer’s agreed price and offer terms when public offers change. Annual base-price savings are separate from introductory promotions.

## Offsite payments and monitoring

Jafar collects payment outside this application and manually records it here. He may use a third-party service such as Lemon Squeezy or Payoneer; no provider integration or availability is assumed. The package system itself does not collect or automatically verify payments.

Jafar must be able to see who paid, the USD amount, and the duration covered, alongside their assigned package and renewal status. Subscription terms and introductory offers still apply when collection is offsite. Exact receipt fields, balance handling, coverage calculation, and overdue behavior are being settled against the existing manual-payment workflow.

This plan extends the earlier onboarding contract’s monthly-only scope. Its USD-only currency and offsite-collection boundaries remain in force. Contractor recording of payments from their own clients remains a separate CRM workflow.

## Customer editions

Published editions preserve the package terms customers receive. A later change to features, limits, or price does not automatically change an existing customer's edition. Moving that customer requires Jafar's manual assignment. This is the user's blueprint/copy analogy; it does not decide whether implementation duplicates records or references an immutable shared version.

## Still unclear

- Which optional capabilities are selectable and how dependent capabilities are explained and validated.
- Which settings and limits can be tuned for each capability.
- Package creation, duplication, naming, ordering, archival, restoration, and unused-draft deletion.
- Draft saving, exact publication review, and concurrent edit behavior.
- Detailed introductory-period rules, billing-interval changes, manual payment records, partial/excess payments, coverage dates, and overdue behavior.
- Customer assignment confirmation, effects on payment terms, overrides, and downgrade consequences.
- Whether customer-specific editions or existing overrides serve negotiated exceptions.
- Exact scope of replacing old code and resetting test assignments, followed by approved build parts and verification.

## Not doing

- In-app payment collection or automatic provider verification — Jafar receives and confirms payments offsite.
- Automatic movement of existing customers to a newly published edition — Jafar wants manual assignment.
- Treating a newly typed feature name as implemented functionality — capabilities require actual application behavior.
- Deleting or resetting application data during planning — this session authorized a campaign handoff only.

## Research

- [Feature inventory and proposed builder controls](research/package-feature-controls-2026-09-29.md).

- [Introductory offer patterns and proposed rules](research/package-introductory-offers-2026-09-29.md).

- [Package audit and primary-source comparisons](research/package-flexibility-audit-2026-09-29.md).
- Earlier [onboarding contract](jafar-onboarding-implementation-contract.md) and [versioning decision](adr/0001-paid-prospect-provisioning-and-versioned-packages.md) provide context; this replacement plan remains incomplete.
