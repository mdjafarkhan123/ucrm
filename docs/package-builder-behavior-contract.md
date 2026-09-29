# Package builder

**Status:** Planning — resumed on 2026-09-29. The direction below is confirmed; the complete behavior and implementation plan are not approved yet.

## Summary

Jafar builds packages in the Jafar workspace by choosing supported capabilities and tuning their settings and limits, like selecting items from a storeroom. He expects to offer two packages initially; this is not a requested two-package ceiling. Each customer receives a particular published edition, including its features, limits, and price. Editing the offer creates a new edition. Existing customers keep their assigned edition until Jafar manually assigns a newer one. The application currently has only fake organizations and test data, so preserving real customer contracts during replacement is unnecessary.

## Building packages

The builder lets Jafar select supported application capabilities and tune their configuration. Every package includes customers, requests, quotes, jobs, invoices, and payment recording. Normal scheduling and essential customer access to quotes and invoices are also included in every package. Separately selectable extras are sales pipeline, shared inbox, website chat, marketing email, Google review requests, custom automations, and advanced reports. Adjustable business allowances include team size, email allowances, website chat allowances, and the number of active automations; Jafar sets values for each package. The builder explains supporting feature requirements and lets Jafar add them, then blocks publication until the combination works. An extra can be published only after its application behavior and enforcement are verified. Safety protections remain in force for every package and are separate from sellable allowances. The team allowance counts the owner, active staff, and pending invitations; a seat becomes available when membership ends or an invitation expires. Email and accepted website chat allowances reset each monthly service period, including for yearly customers. Seats, chat widgets, and active automation recipes are concurrent counts. At a limit, the app explains why new use stops and preserves existing records. Essential emails such as quotes, invoices, receipts, security notices, and direct replies continue under the existing Communications policy and are counted. Optional operational email beyond its allowance uses prepaid Communication Balance or pauses when that balance is insufficient. Marketing email retains its separate allowance and sending rules. Accepted website chat conversations reset monthly even for yearly customers, superseding the former yearly-period chat allowance. Counting moments and boundary cases must be verified against each feature before sale. Packages can be public offers or private negotiated offers. The current implementation must not constrain the new product design to Starter, Growth, and Elite.

## Pricing

Approved 2026-09-29: packages have independently set monthly and yearly prices in USD only. Yearly means one upfront payment for the year.

Introductory offers support percentage or fixed-amount discounts, three/six-month presets and custom duration, and separate first-year offers for yearly customers. Controls include eligible packages and billing intervals, customer eligibility, claim dates, redemption caps, and optional promotion codes or automatic application. Only one promotion applies at a time. With offsite collection, Jafar applies a promotion code when recording the customer's agreed package; the claim and discount are saved in their history. Show the introductory price, duration, and subsequent normal price clearly. Preserve the customer’s agreed price and offer terms when public offers change. Annual base-price savings are separate from introductory promotions.

## Package catalog and publishing

Jafar may create any number of named packages, duplicate a package into a new draft, choose public or private visibility, and set display order. He can save drafts freely and publish only after reviewing the exact saved terms. Archiving stops an offer being chosen by new customers while existing customers keep their assigned edition; Jafar may restore the offer later. Only unused drafts with no dependent records can be deleted. Publishing a revised offer creates a new edition and never silently moves assigned customers.

## Offsite payments and monitoring

Jafar collects payment outside this application and manually records it here. He may use a third-party service such as Lemon Squeezy or Payoneer; no provider integration or availability is assumed. The package system itself does not collect or automatically verify payments.

Jafar must be able to see who paid, the USD amount, and the duration covered, alongside their assigned package and renewal status. Subscription terms and introductory offers still apply when collection is offsite. The system records each monthly or yearly amount due separately from money Jafar confirms receiving offsite. It shows the amount paid, remaining balance, and extra credit. A partial payment leaves a balance; an overpayment becomes credit and does not silently extend coverage. Jafar confirms the exact dates a payment covers before paid-through moves. The view shows the upcoming renewal. The existing seven-calendar-day grace period after coverage ends remains. For each offsite receipt, Jafar records received date, USD amount, provider or method, private reference, and optional note. A correction appends a reasoned adjustment and retains the original. Partial payment leaves the service period unpaid until the agreed amount is covered. Extra money remains credit until Jafar explicitly applies it to a later period or records an offsite refund; each action stays in history. The seven-day grace allows normal access with an overdue warning. After grace, access is suspended until Jafar confirms payment or an explicit exception; records remain preserved.

This plan extends the earlier onboarding contract’s monthly-only scope. Its USD-only currency and offsite-collection boundaries remain in force. Contractor recording of payments from their own clients remains a separate CRM workflow.

## Customer editions

Published editions preserve the package terms customers receive. A later change to features, limits, or price does not automatically change an existing customer's edition. Moving that customer requires Jafar's manual assignment. Before moving to a smaller edition, the app previews seats, widgets, or automations above the new allowance; Jafar resolves excess active resources before assigning it, while history and customer records remain. An edition move leaves the paid-through date and recorded payments unchanged. Jafar separately confirms any price difference and the next service period. The customer's introductory discount and billing interval stay fixed until a new explicit agreement; Jafar chooses its effective date and any price adjustment. Enduring negotiated price or feature terms use a private published edition. Temporary feature and limit exceptions use a reasoned override with an effective period and end date. The contractor's actual agreed terms appear together. This is the user's blueprint/copy analogy; it does not decide whether implementation duplicates records or references an immutable shared version.

## Still unclear

- Verify feature-specific counting moments and boundary cases, including email/chat period resets and existing active resources.
- Draft concurrent-edit behavior and precise treatment of visibility, price, and promotion edits.
- Exact start and expiry of introductory periods; credit allocation ordering and late-payment corrections.
- Customer assignment confirmation, pricing of mid-period moves, and adjustment handling.
- Exact scope of replacing old code and handling fake test assignments, followed by approved build parts and verification.

## Not doing

- In-app payment collection or automatic provider verification — Jafar receives and confirms payments offsite.
- Automatic movement of existing customers to a newly published edition — Jafar wants manual assignment.
- Treating a newly typed feature name as implemented functionality — capabilities require actual application behavior.
- Contractor-facing notification and account/offer history screens — tracked as separate work, while the builder supplies their package and payment facts.
- Deleting or resetting application data during planning.

## Research

- [Feature inventory and proposed builder controls](research/package-feature-controls-2026-09-29.md).

- [Introductory offer patterns and proposed rules](research/package-introductory-offers-2026-09-29.md).

- [Package audit and primary-source comparisons](research/package-flexibility-audit-2026-09-29.md).
- [Feasibility check and implementation boundaries](research/package-builder-feasibility-2026-09-29.md).
- Earlier [onboarding contract](jafar-onboarding-implementation-contract.md) and [versioning decision](adr/0001-paid-prospect-provisioning-and-versioned-packages.md) provide context; this replacement plan remains incomplete.
