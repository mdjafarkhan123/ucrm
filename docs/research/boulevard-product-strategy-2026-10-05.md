# Boulevard product research and Uplift multi-vertical strategy

**Research date:** 2026-10-05  
**Scope:** Boulevard's current product, why appointment-based self-care businesses use it, and whether Uplift Contractors CRM should also serve salons, spas, and medspas.  
**Source policy:** First-party Boulevard product pages, support center, developer documentation, and the current Uplift repository only. Boulevard's outcome claims are identified as vendor claims, not independent proof.

## Executive answer

The idea is technically possible, but **Uplift should not simply add Boulevard's features and hide contractor menus**. Contractors and self-care businesses share a useful platform foundation—organizations, locations, clients, staff, calendars, communication, marketing, payments, files, permissions, and reporting—but their operational engines are different.

- A contractor moves work through **Lead → Request → Quote → Job → Invoice → Payment**, usually around a property and visits. That is Uplift's declared core workflow ([project instructions](../../AGENTS.md)).
- A salon or spa moves demand through **discover/select services → find provider/resource availability → book → confirm/intake → arrive → perform service → check out → rebook/retain**. Boulevard's own booking, scheduling, appointment, profile, and order documentation confirms this appointment-centered model ([client booking experience](https://support.boulevard.io/en/articles/5941525-the-client-booking-experience), [Precision Scheduling](https://support.boulevard.io/en/articles/6110033-precision-scheduling), [appointment API](https://developers.joinblvd.com/2026-06/admin-api/api-reference/queries/appointment)).
- A medspa adds a third, clinical layer: protected health information (PHI), medical history, treatment documentation, photos, clinician review/sign-off, prescriptions, stronger identity/access controls, and a Business Associate Agreement (BAA). Boulevard sells this as an add-on and gives customers mandatory configuration and operational requirements; it is not achieved by merely labeling ordinary forms “HIPAA compliant” ([Medspa Add-on](https://support.boulevard.io/en/articles/9084775-medspa-add-on), [PHI security requirements](https://support.boulevard.io/en/articles/8550292-protected-health-information-phi-security-requirements)).

**Recommendation:** finish Uplift's production-grade contractor product first. Then validate and build a separate **Self-Care edition**, starting with non-clinical salons/spas. Reuse a shared platform underneath, but give each edition its own workflow, navigation, language, permissions, and data rules. Treat medspa as a later, separately approved clinical product—not as a quick salon toggle and not as “healthcare in general.”

## 1. What Boulevard actually is

### Confirmed facts

The correct public product domain is **joinblvd.com**, not boulevard.com (the latter is Boulevard Brewing Company). Boulevard's operational dashboard uses `dashboard.boulevard.io`, its support center uses `support.boulevard.io`, and its developer portal uses `developers.joinblvd.com` ([official developer portal](https://developers.joinblvd.com/), [client API authentication](https://developers.joinblvd.com/2026-06/client-api/authentication)).

Boulevard describes itself as a scheduling and point-of-sale platform for appointment-based businesses. Its named markets are medspas, salons, spas, barbers, massage businesses, and nail salons, including multi-location, franchise, enterprise, and individual-professional use cases ([salon product page](https://www.joinblvd.com/salon-software), [medspa product page](https://www.joinblvd.com/medical-spa-software)). This is narrower than “all healthcare.”

The public product is sold in editions/plans plus add-ons. On 2026-10-05, the public pricing page showed salon/spa plans from Essentials through Enterprise, with per-location pricing and separate charges for items such as forms, QuickBooks, ePrescribe, messaging, and marketing. It also showed temporary promotional pricing, so these numbers should not be treated as durable product requirements ([current pricing](https://www.joinblvd.com/pricing)).

### Inference

Boulevard's true product category is best understood as a **client-experience and revenue operating system for scheduled self-care services**, not a generic CRM and not merely a calendar. The calendar is the center, but the surrounding system protects capacity, captures payment, records the visit, compensates staff, and drives the next booking.

## 2. Core workflow and data model

### Confirmed workflow

1. **Configure the business:** business, one or more locations, staff/providers, roles and permissions, service catalog, provider-specific service rules, prices/durations, rooms/equipment, working schedules, taxes, policies, and payment processing. Service price and duration can vary by staff and location ([service API](https://developers.joinblvd.com/2026-06/admin-api/api-reference/types/Service), [advanced service customization](https://support.boulevard.io/en/articles/5941407-advanced-service-customization), [resource scheduling](https://support.boulevard.io/en/articles/5941355-resource-scheduling)).
2. **Acquire and book:** the client selects services and possibly modifiers/provider, authenticates or creates a profile, sees available times, optionally joins a waitlist, supplies a valid card, pays any deposit, and completes the booking. Confirmation and reminder messages follow ([client booking experience](https://support.boulevard.io/en/articles/5941525-the-client-booking-experience), [waitlist](https://support.boulevard.io/en/articles/5941433-waitlist), [deposits](https://support.boulevard.io/en/articles/5941467-pre-payments-and-deposits)).
3. **Protect and optimize capacity:** availability accounts for the client, provider, service timing, and required rooms/equipment. Boulevard separates hands-on duration, processing time, finishing time, and transition/cleanup/documentation time. Its Precision Scheduling ranks times to preserve useful calendar blocks and coordinate multiple providers/resources ([service timing](https://support.boulevard.io/en/articles/5941395-service-timing-options), [Precision Scheduling](https://support.boulevard.io/en/articles/6110033-precision-scheduling)).
4. **Prepare and deliver:** staff see appointment details and client history; forms can collect intake, consent, medical history, and waivers, while staff-only charts can record SOAP notes and treatments. Forms/charts are stored on the client profile ([forms and charts](https://support.boulevard.io/en/articles/6989798-forms-and-charts-building-forms-and-charts), [client profiles](https://support.boulevard.io/en/articles/5941460-client-profiles)).
5. **Arrive, perform, and check out:** appointment state includes confirmation, arrival, cancellation/no-show, and paid/finalized status. Checkout can connect services, retail products, discounts, tips, gift cards, account credits, vouchers, memberships, packages, payment/refund/dispute records, and the appointment's order ([appointment statuses](https://support.boulevard.io/en/articles/5941417-appointment-status-icons), [appointment API](https://developers.joinblvd.com/2026-06/admin-api/api-reference/queries/appointment), [order line model](https://developers.joinblvd.com/2026-06/client-api/api-reference/types/OrderLine)).
6. **Retain and manage:** client profiles unify contact information, history, payment items, forms/charts, products, memberships, and packages. Businesses can rebook, message, market, run memberships, track inventory, calculate commissions, and report on utilization, retention, sales, and staff performance ([client profiles](https://support.boulevard.io/en/articles/5941460-client-profiles), [memberships](https://support.boulevard.io/en/articles/10012451-memberships-creating-a-membership-plan), [reporting permissions](https://support.boulevard.io/en/articles/15609508-reporting-permissions), [payroll/commissions](https://support.boulevard.io/en/articles/5941315-payroll)).

### Confirmed conceptual entities

The public API and data-share documentation expose a model centered on:

- Business → locations
- Location → staff schedules, resources, services, products, and appointments
- Client → appointments, forms/charts, notes, cards/credits/gift cards/vouchers, memberships, packages, and order history
- Service → category, options/modifiers/add-ons, staff/location overrides, price, and multiple timing blocks
- Appointment → client, location, one or more appointment services, staff, resources, forms, status/cancellation, and eventual order
- Order → service/product/membership/package/gift-card/credit/gratuity lines, taxes, discounts, payments, refunds, and disputes
- Staff → role/permissions, schedule/timecards, services performed, compensation/commissions, and performance

This is supported by Boulevard's [schema guide](https://developers.joinblvd.com/data-share/tables-and-schema), [Admin API root queries](https://developers.joinblvd.com/2026-06/admin-api/api-reference/types/RootQueryType), [service type](https://developers.joinblvd.com/2026-06/admin-api/api-reference/types/Service), and [appointment type](https://developers.joinblvd.com/2026-06/admin-api/api-reference/queries/appointment).

## 3. Major feature groups

Boulevard itself groups the product into client experience, operational management, and growth ([features overview](https://www.joinblvd.com/features)). In practical terms:

| Product area | Important capabilities confirmed in first-party material |
| --- | --- |
| Booking and front desk | Website self-booking, provider/service selection, optimized availability, waitlist, recurring/group appointments, confirmation/rescheduling/cancellation, client portal, reminders, arrival/front-desk states |
| Scheduling engine | Provider shifts, multi-service appointments, processing/finishing/transition time, rooms/chairs/equipment, provider-specific pricing/duration, gap optimization |
| CRM / client record | Contact and preference data, appointment/order history, notes, cards/credits/vouchers/gift cards, memberships/packages, forms/charts, product recommendations |
| POS and payments | Integrated checkout, card on file, deposits/prepayment, cancellation/no-show fees, refunds/disputes, tips, retail, gift cards, credits, buy-now-pay-later |
| Catalog and inventory | Services, options/modifiers/add-ons, retail products, stock, purchase orders, and usage-based product tracking; this supports medspa pricing such as injectable units ([usage-based pricing](https://support.boulevard.io/en/articles/5941350-tracking-and-charging-for-products-used-during-services)) |
| Retention and revenue | Memberships, packages/vouchers, loyalty/referrals, two-way messages, SMS/email blasts, prebuilt automated campaigns, rebooking and win-back workflows ([automated campaigns](https://support.boulevard.io/en/articles/6249878-automated-campaigns-faq)) |
| Workforce | Staff permissions, schedules, time clock, service/product/package/membership/tip commissions, performance and utilization reports |
| Clinical medspa | Clinical profile, intake/consent/charting, SOAP/treatment records, photos and markup, supervisor/medical-director sign-off, medication/allergy data, and optional ePrescribe |
| Administration and platform | Multi-location controls, granular permissions, reporting, audit log, APIs/integrations, security/compliance controls, onboarding/data migration |

Boulevard has also introduced an AI receptionist in beta. Its current behavior is deliberately bounded: it answers inbound calls, uses configured service/location data, sends booking or portal links, answers common questions, transfers or takes messages, and stores transcripts/summaries. It does not directly complete voice bookings or handle complex consultative matching ([AI Receptionist overview](https://support.boulevard.io/en/articles/16105086-ai-receptionist-overview), [AI Receptionist FAQ](https://support.boulevard.io/en/articles/16105159-ai-receptionist-frequently-asked-questions)).

## 4. Why businesses use Boulevard, and what appears differentiated

### Confirmed product mechanisms

- **More sellable time:** Precision Scheduling tries to avoid revenue-killing gaps instead of presenting every mathematically valid slot, and it accounts for multi-provider/resource transitions ([Precision Scheduling](https://support.boulevard.io/en/articles/6110033-precision-scheduling)).
- **Less front-desk work:** clients can book, authenticate, complete forms, reschedule/cancel, and view appointments through self-service; automated notifications and the client portal reduce routine calls ([client booking](https://support.boulevard.io/en/articles/5941525-the-client-booking-experience), [client portal](https://support.boulevard.io/en/articles/8648439-client-portal)).
- **No-show and late-cancel protection:** online bookings can require a valid card, deposits can be configured by service/provider, and cancellation windows/fees are configurable ([online booking account](https://support.boulevard.io/en/articles/6950782-online-booking-account), [cancellation policies](https://support.boulevard.io/en/articles/5941349-cancellation-policies-and-fees)).
- **One continuous record:** booking, visit history, forms/charts, payment assets, purchases, memberships, and packages sit on one client profile ([client profiles](https://support.boulevard.io/en/articles/5941460-client-profiles)).
- **Repeat revenue:** recurring memberships automatically charge cards and add vouchers/credits; packages, marketing automation, rebooking, referrals, and loyalty encourage return visits ([membership plans](https://support.boulevard.io/en/articles/10012451-memberships-creating-a-membership-plan), [automated campaigns](https://support.boulevard.io/en/articles/6249878-automated-campaigns-faq)).
- **Industry-specific operations:** processing time, room/equipment contention, tips, retail attachment, commissions, usage-based consumables, treatment documentation, and provider review are modeled directly rather than assembled from generic CRM fields.

### Inference, not independently verified market fact

The strongest differentiator is likely **depth around the appointment economics**, especially Precision Scheduling combined with provider/resource rules, card/deposit/no-show protection, integrated checkout, and retention. A generic CRM can store a contact and appointment, but it does not automatically understand that a colorist is free during processing time, a laser room cannot be double-booked, a treatment consumes units from inventory, or a membership voucher should be redeemed at checkout.

Boulevard publishes improvement figures and case studies, but they are vendor-produced and sometimes explicitly described as estimated aggregated results. They are useful hypotheses, not reliable proof of the results Uplift would achieve. Uplift should measure booking conversion, utilization, no-show rate, rebooking, retention, average ticket, and front-desk time in its own pilots before making capacity or revenue claims.

## 5. Medspa and healthcare constraints

### Confirmed facts

Boulevard's public material says its Medspa add-on includes HIPAA coverage, BAA signing, additional security settings, a clinical client-profile section, photo markup, reviewer sign-off, HIPAA-oriented configuration guidance, and access to purchase clinical features such as ePrescribe ([Medspa Add-on](https://support.boulevard.io/en/articles/9084775-medspa-add-on)). Its pricing page describes ePrescribe as EPCS-compliant support for controlled and non-controlled prescriptions through the Surescripts network ([pricing](https://www.joinblvd.com/pricing)).

Boulevard's own PHI requirements make the customer's obligations explicit: subscribe to the appropriate coverage, complete the BAA, set automatic logout, configure least-privilege permissions, keep SSL enabled, store PHI only in intended fields, keep PHI out of email/text, deactivate former staff, avoid unsafe shared client profiles, conceal service details in notifications, use strong authentication, and train staff ([PHI security requirements](https://support.boulevard.io/en/articles/8550292-protected-health-information-phi-security-requirements)). It also provides role-based access, IP restrictions, two-step verification, and audit logs; Boulevard says it undergoes an annual SOC 2 audit and is PCI Level 1 compliant ([data security](https://www.joinblvd.com/features/data-security)).

### Strategic implications for Uplift

1. **“Medspa” is not the same as “healthcare.”** Boulevard's confirmed scope is appointment-based self-care and medical aesthetics. General practices, hospitals, mental health, dental, pharmacy, insurance billing, lab workflows, referrals, and emergency care have different records and regulation. Uplift should not promise those markets based on this research.
2. **Compliance is an operating system, not a badge.** Uplift would need contractual coverage, data classification, least-privilege access, immutable/reviewable audit evidence, secure patient identity, session controls, approved communication behavior, retention/deletion policies, incident response, vendor agreements, staff processes, and jurisdiction-specific legal review before storing PHI.
3. **The current geographic ambition makes this larger.** HIPAA is US-specific. Uplift targets Europe, the UK, Canada, Australia, and the US; the reviewed Boulevard pages do not establish a single compliance design that covers all of those jurisdictions. Each launch country would need an approved legal/data-residency/health-record assessment before clinical release.
4. **Clinical records should be isolated by capability and policy.** Hiding a menu is not access control. Clinical data needs server-enforced authorization, explicit clinical roles, protected APIs/storage/logs, safe notifications, and restricted exports/support access.

## 6. What Uplift can reuse and what it must add

The current route inventory already shows contractor-focused clients, requests, quotes, jobs, invoices, payments, schedule, communications, marketing, files, reviews, team/security, forms, and price-book areas ([current app routes](../../src/routes/(app))). That creates meaningful reuse, but not a near-complete Boulevard product.

### Good shared platform candidates

- Tenant/organization, locations, branding, subscription, and feature entitlements
- People/party identity, contact details, consent, deduplication, and communication preferences
- Staff accounts, roles, permissions, invitations, sessions, and audit foundations
- Calendar primitives, availability, notifications, communication inbox, campaigns, files/media, and search
- Money/tax/payment abstractions, reporting infrastructure, webhooks/integrations, and operational monitoring

### Contractor-only domain

- Properties/service addresses
- Requests and site assessment
- Quotes, deposits, approvals, and change scope
- Jobs, visits, crews, checklists, materials, work photos, and field progress
- Progress/final invoices and contractor payment/collection behavior

### Self-care-only domain that must be built

- Service catalog with categories, provider/location rules, modifiers/add-ons, variable price, and four-part timing
- Provider calendars plus rooms/chairs/equipment and a real availability/optimization engine
- Appointment/cart lifecycle, group/recurring booking, waitlist, confirmation, arrival, no-show/cancellation, rebooking
- Consumer self-booking overlay and secure client portal
- Card-on-file, service/provider deposits, late-cancel/no-show fees, tips, POS/register/closeout, refunds/disputes
- Retail stock, purchase orders, service-consumable usage, gift cards, account credit, vouchers
- Membership/package configuration, recurring billing, commitment/pause/cancel/past-due behavior, benefit redemption
- Staff service assignment, commissions, time clock, utilization/retention/rebooking reporting
- Self-care-specific automated marketing and attribution

### Additional medspa-only domain

- Clinical profile and PHI classification
- Intake/medical history/consent, staff-only charts, versioning, signatures, expiration, amendments
- Treatment photos and markup, reviewer/medical-director queue, approval/rejection trail
- Medication/allergy/prescription workflows and a regulated prescribing partner integration
- Stronger identity verification, session/access policy, clinical audit log, safe communications, BAA/vendor controls
- Jurisdiction-by-jurisdiction rules and clinical governance

## 7. Recommended product architecture

Do not create one huge application full of `if business_type === ...` checks. Use a **shared platform with vertical editions and capability entitlements**:

```text
Shared platform
├── identity, organizations, locations, people, staff, permissions
├── communications, marketing, files, payments, reporting, integrations
├── Contractor edition
│   └── properties, requests, quotes, jobs/visits, invoices
└── Self-Care edition
    ├── services, providers/resources, appointments, POS, memberships
    └── Clinical capability (later)
        └── PHI, charts, photos, sign-off, prescriptions, clinical controls
```

The edition chosen during onboarding should provision an approved capability set and tailored vocabulary/navigation. Enforcement must exist in the database/API permission layer as well as the interface. Shared concepts should remain neutral internally—such as `party`, `location`, `staff_member`, `payment`, and `communication`—while each edition presents natural language such as **job/crew/property** or **appointment/provider/client**.

An organization should not be permanently trapped by one onboarding choice. The data model can support multiple capabilities later, but mixed businesses should only be enabled after their workflows are explicitly designed; otherwise the product becomes confusing and impossible to support.

## 8. Practical sequence and decision gates

### Recommended sequence

1. **Protect the current promise:** complete and harden the contractor edition for the first paying contractor customer.
2. **Validate before building:** interview roughly 10–15 owners/front-desk managers and several providers across one narrow launch segment. Map their booking, cancellation, checkout, rebooking, payroll, and reporting failures. Confirm willingness to switch and pay.
3. **Choose one non-clinical beachhead:** a salon or spa is safer than medspa because the core appointment/POS/member value can be proven without storing PHI or prescribing.
4. **Design the shared boundary:** separate shared platform services from contractor-specific tables/routes before adding the new edition. Do not rename contractor concepts into vague universal concepts unless the underlying rules truly match.
5. **Build a complete vertical slice:** service/provider/resource setup → public booking → reminders/deposit → front desk/visit → checkout/tip → rebook → basic reporting. A calendar-only MVP is not a competitive Boulevard alternative.
6. **Pilot and measure:** booking conversion, calendar utilization, double-booking incidents, no-shows, checkout time, rebooking, repeat rate, average order, payment failures, support volume, and staff adoption.
7. **Only then assess medspa:** commission a formal US clinical/compliance design and legal review, select prescribing/payment partners, implement the clinical capability, and pilot with tightly controlled medical-aesthetics businesses. Repeat jurisdictional assessment before any launch outside the US.

### Go/no-go questions

- Can Uplift fund and support a second complete workflow without delaying the promised contractor product?
- Is there a specific first self-care segment and launch country, rather than “salon, medspa, and healthcare” together?
- Can Uplift match the minimum operational system—not just booking—including POS, deposits/cancellations, memberships, inventory, commissions, and reporting?
- Is there measured demand from businesses willing to migrate their client, card/membership, service, and appointment data?
- For medspa, is Uplift prepared to accept the legal, security, support, and incident-response duties around PHI and clinical workflows?

## Bottom line

The strategic instinct is good: Uplift's existing CRM, communications, payments, schedule, and team foundations could support more than contractors. The proposed execution—build everything and hide the irrelevant features—is too shallow. It risks producing two incomplete products and creates dangerous assumptions for clinical data.

The strongest path is **one platform, distinct editions**. Keep Contractors complete. Prove a full Salon/Spa edition next. Add Medspa only as a deliberately governed clinical capability. That preserves reuse without pretending that a job and an appointment, or a client note and a medical chart, are the same thing.
