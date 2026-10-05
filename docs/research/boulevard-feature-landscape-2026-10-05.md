# Boulevard feature landscape — first pass

**Checked:** 2026-10-05. **Status:** Research in progress; this is a sourced area map, not the complete feature inventory or an approved build specification.

Collection pages confirm that capabilities are documented. They do not establish all operating rules, plan availability, current rollout, or equivalence to our app. Expand each area into feature-level entries after reading its articles. All release assignments below remain unassigned; all delivery states are Needs research. Suggested industry relevance is our planning classification, not a verified vendor entitlement rule.

## Area map

| ID | Area | Documented capabilities to investigate | Relevance | Evidence |
| --- | --- | --- | --- | --- |
| BL-01 | Staff | Roles, permissions, shifts, timecards, commissions | Shared | [Dashboard](https://support.boulevard.io/en/collections/3322720-boulevard-dashboard) |
| BL-02 | Clients | Profiles, merging, notes, accommodations, wallet, credits, booking restrictions | Shared | Dashboard |
| BL-03 | Services | Categories, add-ons, modifiers, timing, staff-specific settings | Shared | Dashboard |
| BL-04 | Scheduling | Recurrence, resources, waitlists, groups, rescheduling, cancellations | Shared | Dashboard |
| BL-05 | Checkout | Deposits, partial payments, refunds, receipts, gift cards, closeout | Shared | Dashboard |
| BL-06 | Repeat business | Membership billing, updates, packages, same-visit redemption | Shared | Dashboard |
| BL-07 | Inventory | Suppliers, purchase orders, stock adjustments, returns, service consumables | Shared where relevant | Dashboard |
| BL-08 | Care documentation | Forms, charts, photos, connected fields, copying, sign-off | Clinical priority; some shared forms | Dashboard |
| BL-09 | Conversations | Messaging, number setup, caller identification, delivery errors | Shared | Dashboard |
| BL-10 | Notifications | Confirmations, reminders, instructions, receipts, ratings, privacy settings | Shared with clinical differences | Dashboard |
| BL-11 | Customer booking | Booking overlay, account access, portal, scheduling adjustments, direct service/category links, gratuity settings | Shared | [Self-booking collection](https://support.boulevard.io/en/collections/3322731-client-self-booking) |
| BL-12 | Marketing | One-time email/text campaigns, audience filtering, templates, campaign reports, automation, consent import and preferences | Shared; clinical use needs review | [Marketing collection](https://support.boulevard.io/en/collections/3322732-boulevard-marketing) |
| BL-13 | Reporting | Business/sales dashboards; filtered and saved views; export and sharing permissions; appointments, retention, revenue, memberships, inventory, staff, disputes and balance reporting | Shared | [New reporting collection](https://support.boulevard.io/en/collections/19737017-new-reporting-experience) |
| BL-14 | Prescribing | Prescriber/assistant setup, prescription management, allergy/medication history, migration and pricing | Clinical; separate feasibility decision | [ePrescribe collection](https://support.boulevard.io/en/collections/19446920-eprescribe) |

The report collection includes beta guidance, while the support home separately lists legacy reports. Reconcile current versus old behavior before selecting a reference; two articles need not imply two features. The prescribing collection identifies ScriptSure: matching a vendor feature may require a partner service rather than a custom implementation.

## Supplemental official-source findings

These families were checked in a bounded research pass. Costs, eligibility, sync semantics and detailed behavior still require verification.

| ID | Family | Confirmed public capability | Qualification and source |
| --- | --- | --- | --- |
| BL-15 | Clinical review | Review queue, pending-chart overview, reusable signatures and permission-controlled bulk actions | [Sign-off release](https://changelog.joinblvd.com/faster-more-flexible-sign-off-for-forms-charts-342962); existence does not approve our clinical policy |
| BL-16 | Audit history | Searchable business and clinical access activity, attribution and changed values | [Audit-log release](https://changelog.joinblvd.com/track-who-did-what-at-your-business-with-our-new-audit-log-338848); historical coverage is bounded |
| BL-17 | AI reception | Call handling, booking-related assistance, lead capture and handoff | [Beau beta release](https://changelog.joinblvd.com/never-miss-a-chance-to-book-with-new-ai-receptionist-beta-free-to-try-until-the-end-of-november-344864); beta, enduring price and boundaries unverified |
| BL-18 | Client financing | Affirm/Klarna checkout options for eligible transactions | [Financing release](https://changelog.joinblvd.com/buy-now-pay-later-is-now-live-on-boulevard-344077); provider eligibility is not implied for our product |
| BL-19 | Integrations | Calendar and social booking, Shopify, QuickBooks, Okta, hotel charges, Zapier, review and specialist service connections | [Integration directory](https://www.joinblvd.com/integrations); listing is not a complete sync or entitlement contract |
| BL-20 | Developer access | Admin, Client and card-tokenization APIs, custom apps and booking SDK | [Developer portal](https://developers.joinblvd.com/); search-indexed official text indicates Enterprise access, direct page did not render, so entitlement needs confirmation |
| BL-21 | Mobile and security | Business-line messaging in Professional App; employee verification/session controls | [Release feed](https://changelog.joinblvd.com/); rolling availability and individual behavior need article-level verification |
| BL-22 | Commercial operations | Tier allowances, merchant disputes, payouts, payment hardware, fee-sharing, paid forms and accounting add-ons | [Pricing](https://www.joinblvd.com/pricing); fetched view was Salon & Spa, not verified Medspa tier parity |
| BL-23 | Multi-location | Location-aware permissions and client primary-location behavior | [Release feed](https://changelog.joinblvd.com/); later planning under approved single-location launch scope |

Business financing (Capital), the full AI family and enterprise/franchise administration remain discovery items. This map separates external financial services and partner integrations from ordinary application features; recording a vendor offering creates no promise to reproduce it.

## Coverage checklist

- [x] Map Dashboard capability families.
- [x] Map customer self-booking, marketing, reporting and prescribing collections.
- [ ] Read Getting Started and Merchant Information for setup, migration and payment requirements.
- [ ] Cover Duo and Professional apps, including which tasks require hardware or native apps.
- [ ] Reconcile Medspa/add-ons, integrations and current pricing entitlements.
- [ ] Cover Offset, disputes, financing, AI receptionist, enterprise and franchise offerings.
- [ ] Cross-check recent release notes and main feature catalog against the map.
- [ ] Expand grouped areas to individual features with article-level sources, exceptions and industry availability.
- [ ] Check duplicates and older/replaced experiences; explicitly record inaccessible or unclear behavior.

[Support home](https://support.boulevard.io/en/) is the collection coverage index. Vendor support, academy and referral programs should be classified separately from software features rather than silently omitted or counted as application functions.

## Next behavior research

Proposed first area: service catalog and appointment scheduling. Duration, staff eligibility, rooms/equipment, and cancellation behavior connect booking, clinical forms, payment and reminders. This is a research sequencing recommendation, not initial-release approval. Clinical documentation should be checked alongside these dependencies before finalizing the shared behavior.

## Reuse and release limits

Our existing inbox, marketing and automation are candidates for reuse. This source inventory performs no code or live-delivery verification and does not mark them Done for the new edition. US/single-location scope and the specialist-diagnostics exclusion are approved in the product plan. Prescribing, financial products, hardware, beta features and external integrations are inventoried without promising that our first release will provide them.
