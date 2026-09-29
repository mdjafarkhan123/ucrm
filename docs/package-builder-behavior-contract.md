# Package builder

**Status:** Planning — paused at Jafar's request on 2026-09-29. The direction below is confirmed; the complete behavior and implementation plan are not approved yet.

## Summary

Jafar builds packages in the Jafar workspace by choosing supported capabilities and tuning their settings and limits, like selecting items from a storeroom. He expects to offer two packages initially; this is not a requested two-package ceiling. Each customer receives a particular published edition, including its features, limits, and price. Editing the offer creates a new edition. Existing customers keep their assigned edition until Jafar manually assigns a newer one. The application currently has only fake organizations and test data, so preserving real customer contracts during replacement is unnecessary.

## Building packages

The builder lets Jafar select supported application capabilities and tune their configuration. The exact selectable items, dependencies, mandatory capabilities, and tuning controls remain to be planned. The current implementation must not constrain the new product design to Starter, Growth, and Elite.

## Customer editions

Published editions preserve the package terms customers receive. A later change to features, limits, or price does not automatically change an existing customer's edition. Moving that customer requires Jafar's manual assignment. This is the user's blueprint/copy analogy; it does not decide whether implementation duplicates records or references an immutable shared version.

## Still unclear

- Which capabilities are selectable, which are mandatory, and how dependent capabilities are explained and validated.
- Which settings and limits can be tuned for each capability.
- Package creation, duplication, naming, visibility, ordering, archival, restoration, and unused-draft deletion.
- Draft saving, exact publication review, and concurrent edit behavior.
- Monthly versus annual prices, currencies, and billing arrangements.
- Customer assignment confirmation, effects on payment terms, overrides, and downgrade consequences.
- Whether customer-specific editions or existing overrides serve negotiated exceptions.
- Exact scope of replacing old code and resetting test assignments, followed by approved build parts and verification.

## Not doing

- Automatic movement of existing customers to a newly published edition — Jafar wants manual assignment.
- Treating a newly typed feature name as implemented functionality — capabilities require actual application behavior.
- Deleting or resetting application data during planning — this session authorized a campaign handoff only.

## Research

- [Package audit and primary-source comparisons](research/package-flexibility-audit-2026-09-29.md).
- Earlier [onboarding contract](jafar-onboarding-implementation-contract.md) and [versioning decision](adr/0001-paid-prospect-provisioning-and-versioned-packages.md) provide context; this replacement plan remains incomplete.
