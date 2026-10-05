# LifeScan opportunity: a focused clinical booking product, not a Boulevard clone

**Research date / access date:** 2026-10-05  
**Question:** What does LifeScan Health & Wellness publicly appear to need, what is Boulevard doing for that workflow, and what narrow product could Uplift realistically sell to LifeScan and similar referrals?  
**Evidence policy:** LifeScan's public website, Boulevard's first-party product/support material, and the current Uplift repository. Statements are labelled as page evidence, technical observation, or inference. This report does not rely on private facts about the business or its Boulevard account.

## Executive answer

LifeScan changes the strategic answer in an important way. Jafar does not merely have an abstract idea about salons or medspas: he has a direct relationship with one cash-pay clinic that publicly embeds Boulevard, and a referral to another similar business. That is a credible **market signal** and justifies immediate customer discovery.

It is not yet proof that Uplift should build all of Boulevard, or that the two businesses would buy an unfinished replacement. The public evidence points to a much narrower first market:

> **Small, US-based, cash-pay preventive and wellness clinics that sell scheduled screening, consultation, and treatment visits directly to patients.**

The first sellable Uplift product for this niche should be a **clinical front-office and appointment operations edition**: public booking, provider/resource availability, secure patient portal, intake and consent, appointment reminders and preparation instructions, deposits/cancellation rules, checkout, and a secure handoff/export to the clinic's clinical record/results system. It should not initially attempt prescriptions, insurance claims, a general-purpose EHR, laboratory/PACS replacement, or every salon/medspa feature.

However, even this narrow product will handle protected health information (PHI). It cannot be launched safely by reusing an ordinary CRM form and hiding contractor menus. A HIPAA-oriented security and operating boundary, appropriate vendor agreements including BAAs where required, least-privilege access, audit evidence, safe communications, retention/incident procedures, and healthcare legal review are entry requirements—not later polish.

The commercial move now is therefore **paid design-partner discovery**, not speculative full construction and not telling the client to abandon Boulevard immediately.

## 1. What LifeScan publicly appears to be

### Page evidence

The [LifeScan home page](https://lifescanhealthwellness.com/) describes the business as:

- a single-location clinic in Las Vegas, Nevada;
- cash-pay, with no referral or insurance required for its promoted screening flow;
- focused on preventive cardiovascular/vascular screening, body-composition analysis, wellness consultations, and peptide therapy;
- offering services including echocardiogram, carotid ultrasound, lower-extremity arterial and venous ultrasound, ankle-brachial index, and electrocardiogram;
- guiding the patient through **schedule appointment -> visit clinic -> understand next steps**;
- promoting transparent packages and same-day information/guidance.

The [diagnostic page](https://lifescanhealthwellness.com/diagnostic/) adds that studies may be self-referred or ordered by a doctor, are interpreted by a board-certified physician, and produce results patients can share with their doctor. It also advertises a Tuesday-Saturday schedule and transparent cash-pay pricing.

The [about page](https://lifescanhealthwellness.com/about/) emphasizes an unhurried visit, clinical image quality, plain-language guidance, and a patient journey from the first question through the final report.

The public [terms of service](https://lifescanhealthwellness.com/terms-of-service/) describe additional intended workflow:

- online, phone, or in-person appointment requests and confirmations;
- service availability subject to clinical appropriateness and licensed-provider judgment;
- medical history, medication, allergy, implanted-device, intake, and informed-consent collection before care;
- procedure-specific consent for sclerotherapy;
- cancellation, no-show, late-arrival, and preparation rules;
- payment at time of service, prepaid programs, and Good Faith Estimates;
- appointment confirmations, reminders, result notifications, and service messages;
- clinical services involving nurse practitioners, diagnostic sonographers, and a collaborating physician/medical director.

The public [privacy policy](https://lifescanhealthwellness.com/privacy-policy/) says LifeScan considers itself a HIPAA covered entity and expects to collect appointment details, health history, medications, test results, images, EKG/ABI measurements, and body-composition data. It says scheduling, EHR, payment, laboratory, secure-messaging, IT, and hosting vendors handling PHI are bound by business associate agreements. That is the clinic's published position; this research does not independently determine its legal status or whether every described process is already operational.

### Technical observations from the public site

- The booking experience is an embedded Boulevard widget loaded from `joinblvd.com`, with Boulevard's public injector script served from `static.joinboulevard.com`.
- Opening a public **Book now** link on 2026-10-05 displayed the Boulevard business as **Lifescan** and the message: **"Online booking unavailable. We are not taking appointments at this time."** This is a point-in-time observation, not evidence about why booking is unavailable.
- The website links to a Boulevard patient portal at the public `blvd.app` domain.
- The privacy policy and terms contain visible placeholders such as the last-updated date, telephone number, cancellation fee, and professional-corporation name. The service/diagnostic pages also contain repeated or inconsistent copy. This suggests the public launch content is still being finalized, but it does not reveal the clinic's internal readiness.
- The site advertises multiple languages in its header. The reviewed pages do not establish whether booking, forms, care delivery, or staff operations are actually multilingual.

### What cannot be inferred

The public pages do **not** establish:

- LifeScan's Boulevard plan, add-ons, contract price, or satisfaction;
- whether the clinic uses Boulevard for clinical charts, payments, forms, or only booking;
- its live patient volume, provider count, equipment constraints, no-show rate, or revenue;
- its EHR, imaging/PACS, lab, prescribing, payment, or accounting systems;
- whether the second referred business has the same workflow;
- why online booking is currently unavailable;
- whether every service and legal-policy statement on the website is final or currently offered.

Those are interview questions, not facts to fill in by guesswork.

## 2. The actual customer journey the product must support

Combining only LifeScan's public claims produces this working journey:

1. A patient discovers a screening, diagnostic study, consultation, wellness program, or treatment on the website.
2. The patient chooses an appropriate service and time, or asks the clinic for help deciding.
3. The system matches the appointment to a qualified clinician/sonographer and any required room or equipment.
4. The patient receives confirmation, preparation instructions, and service-specific intake/consent requests.
5. Staff review identity, history, medications, allergies, risks, consent, and clinical appropriateness.
6. The patient attends; the clinic performs the scan, analysis, consultation, or treatment.
7. Licensed staff document the encounter; some studies are interpreted by a physician.
8. The patient receives understandable results/next-step guidance and may share results with another doctor.
9. The clinic collects payment, applies any cancellation/no-show policy, and may schedule follow-up or a repeat measurement.

This is not a salon journey with medical wording. The booking and payment mechanics overlap, but steps 4-8 create a clinical record, clinical responsibility, and PHI boundary.

## 3. What Boulevard supplies around this journey

Boulevard's first-party documentation confirms the following mechanisms relevant to LifeScan:

| LifeScan need | Boulevard mechanism | First-party evidence |
| --- | --- | --- |
| Website self-booking | Embedded self-booking overlay with services/prices; confirmation follows booking | [Client booking experience](https://support.boulevard.io/en/articles/5941525-the-client-booking-experience) |
| Deposits and appointment protection | Service/provider deposits; configurable cancellation deadlines and fixed/percentage fees | [Client booking experience](https://support.boulevard.io/en/articles/5941525-the-client-booking-experience), [cancellation policies and fees](https://support.boulevard.io/en/articles/5941349-cancellation-policies-and-fees) |
| Confirmation, reminders, preparation | Email/text booking confirmations and reminders; customizable client instructions; links to forms, appointment management, and policy | [Client notifications](https://support.boulevard.io/en/articles/8447955-client-notifications) |
| Intake and consent | Service-linked forms for intake, medical history, waivers, signatures, expiration, pre-visit delivery, and check-in | [Forms and charts](https://support.boulevard.io/en/articles/6989798-forms-and-charts-building-forms-and-charts) |
| Staff clinical documentation | Staff-only charts, treatment/SOAP templates, photos, copy-forward, and optional medical-director sign-off | [Forms and charts](https://support.boulevard.io/en/articles/6989798-forms-and-charts-building-forms-and-charts), [Medspa add-on](https://support.boulevard.io/en/articles/9084775-medspa-add-on) |
| Patient self-service | Secure portal for appointments, rescheduling/cancellation, forms, history, and profile; extra date-of-birth verification for HIPAA-covered accounts | [Client portal](https://support.boulevard.io/en/articles/8648439-client-portal) |
| PHI-aware operation | BAA, additional security settings, clinical profile, safe-notification defaults, role controls, session guidance, and PHI placement rules | [Medspa add-on](https://support.boulevard.io/en/articles/9084775-medspa-add-on), [PHI security requirements](https://support.boulevard.io/en/articles/8550292-protected-health-information-phi-security-requirements) |

Boulevard explicitly tells PHI-handling customers to use least-privilege permission groups, keep PHI out of ordinary emails/texts, conceal service details in notifications, disable unsafe shared profiles, use short automatic logout, deactivate former staff, obtain appropriate patient notices/consents, and complete a BAA where applicable. This is strong evidence that a scheduling product becomes a healthcare-data product when used for businesses like LifeScan.

### Important limitation

Boulevard's documents prove what the product is designed to support, not which of those capabilities LifeScan currently uses. A replacement scope must be based on a LifeScan workflow interview and observation of its configured account, with permission.

## 4. The narrow product wedge Uplift could sell

### Recommended segment

Do not begin with **salons + medspas + healthcare**. Begin with:

> **US single-location cash-pay preventive/wellness clinics with a small clinical team, scheduled services, transparent prices, and no requirement for Uplift to adjudicate insurance claims.**

LifeScan fits that public description more closely than a salon, hospital, or broad primary-care practice. Similar businesses may include cash-pay screening clinics, body-composition/wellness clinics, and narrowly scoped medical-aesthetics/wellness practices, but each candidate must be screened for workflow and regulation before inclusion.

### Product promise

The defensible first promise is:

> "Turn a clinic website visitor into a prepared, confirmed, paid appointment, while giving staff one secure place to manage the front-office journey and hand the clinical result to the clinic's record system."

This is narrower and more credible than "Uplift replaces Boulevard and every EHR."

### Minimum complete workflow

A product capable of replacing Boulevard for the **front-office scope** at a clinic like LifeScan needs all of the following as one coherent path:

1. **Clinic setup:** locations, services/packages, durations, prices, preparation instructions, clinicians/sonographers, schedules, rooms/equipment, blackout time, and role permissions.
2. **Public booking:** branded website widget/page, service selection, eligibility/triage questions that do not give medical advice, real availability, identity verification, policy acceptance, deposit/card handling, and confirmation.
3. **Secure patient area:** upcoming/past appointments, safe reschedule/cancel rules, required forms, completed consents/instructions, and secure result/document availability only if Uplift is approved to host it.
4. **Service-linked intake:** medical history, medications, allergies, implanted-device/pregnancy safety questions where configured by the clinic, signatures, versioned consent, expiration, and staff review status.
5. **Clinic calendar/front desk:** confirm, arrive, in-service, complete, late-cancel, no-show, reschedule, room/equipment collision prevention, and provider notifications.
6. **Safe communications:** confirmation/reminder templates that can suppress sensitive service details, preparation instructions, outstanding-form prompts, consent/opt-out records, and no PHI in ordinary SMS/email.
7. **Money:** transparent price, deposit/prepayment, cancellation/no-show fee, checkout/receipt/refund, and a basic Good Faith Estimate workflow where the clinic determines it is required.
8. **Clinical handoff:** secure export or integration for the clinic's EHR, imaging/PACS, lab, or physician-interpretation workflow. Uplift should not invent these systems inside version one.
9. **Security/operations:** BAA-capable vendor chain, tenant isolation, least privilege, MFA/session controls, audit history, encryption, backups/restore, incident response, staff offboarding, record retention, and restricted support access.

Leaving out items 2-7 would create a demo, not a trustworthy Boulevard replacement. Leaving out item 9 would make it unsafe to put real patients into the product.

### Explicitly out of the first product

- prescribing or controlled-substance workflows;
- insurance eligibility, prior authorization, claim submission, remittance, or payer contracting;
- a general-purpose EHR;
- diagnostic image storage/viewing and PACS replacement;
- laboratory ordering/results networks;
- clinical decision support, diagnosis, or treatment recommendations;
- multi-country clinical compliance;
- large multi-location enterprise scheduling;
- salon-specific retail inventory, tips, complex commissions, chairs/color processing, and beauty memberships;
- every Boulevard marketing, loyalty, payroll, and AI feature.

Some may become integrations or later capabilities. None is necessary to test whether Uplift can win the narrow cash-pay clinic front-office market.

## 5. What Uplift already has—and what it does not

### Repository observations

The current app has contractor-oriented foundations in [clients](<../../src/routes/(app)/clients>), [schedule](<../../src/routes/(app)/schedule>), [communications](<../../src/routes/(app)/communications>), [payments](<../../src/routes/(app)/payments>), [forms settings](<../../src/routes/(app)/settings/forms>), [team settings](<../../src/routes/(app)/settings/team>), and [price book](<../../src/routes/(app)/settings/price-book>). These may provide reusable organization, identity, permissions, messaging, payment, form-builder, and calendar primitives.

A repository text/route scan did not identify a clinical appointment domain, patient portal, medical chart, PHI classification, provider/resource availability engine, medical-director review flow, or healthcare-specific audit/retention policy. Generic occurrences of words such as `provider`, `consent`, or `appointment_reminders` are not proof of those capabilities; in the current app they often refer to communications providers, marketing consent, or contractor job visits.

### Inference

Uplift has a useful head start at the platform level, but it is not close to being a safe clinic product merely because it already has clients, a schedule, payments, communications, and forms. The expensive part is the rules connecting those pieces and the clinical security/operating boundary.

The right architecture remains one shared platform with separate editions:

```text
Shared Uplift platform
├── organization, identity, staff, permissions, communication, payments, files
├── Contractor edition
│   └── property, request, quote, job/visit, invoice
└── Clinic edition
    └── patient, service, clinician/resource, appointment, intake/consent,
        front desk, checkout, clinical handoff, PHI controls
```

Clinical data and permissions must be enforced in APIs/database/storage, not only by showing or hiding navigation.

## 6. Recommended commercial plan

### Now: turn the two relationships into evidence

Ask LifeScan and the referred business to become **design partners**. A design partner is not promised a complete Boulevard replacement tomorrow. They agree to let Uplift study the workflow, review pain points, test designs, and define a migration/acceptance checklist. In return, they receive influence, hands-on onboarding, clear pricing protection, and the option to adopt only after the product passes the agreed safety and workflow gates.

This discovery should be paid if Jafar is doing meaningful workflow/configuration work. Do not collect live PHI in prototypes or copy Boulevard patient data into Uplift during discovery.

### Interview and observation checklist

With the owner's permission, document:

- every appointment/service type, duration, price, preparation rule, and cancellation/deposit rule;
- which roles perform, supervise, interpret, and communicate each service;
- which rooms/machines/resources can conflict;
- how patients decide what to book and when staff must intervene;
- every intake, consent, signature, expiry, and clinical-review step;
- what Boulevard features are actually used, disliked, missing, or considered indispensable;
- where patient/results data lives: Boulevard, EHR, PACS/imaging, lab, paper, email, or another tool;
- how physician interpretation and result release work;
- payment processor, refunds, Good Faith Estimates, packages, and recurring programs;
- exact reminder/preparation wording and which details must be hidden;
- current reports and migration/export requirements;
- provider count, weekly appointments, no-shows, booking sources, and front-desk time, using real measurements rather than estimates;
- willingness to switch, acceptable migration risk, budget, required support, and the condition under which they would cancel Boulevard.

Repeat the same interview separately with the referred business. Similar websites do not guarantee similar operations.

### Build/no-build gates

Build the clinic edition only if both discovery partners confirm a shared workflow and at least one will sign a paid pilot subject to acceptance criteria. Before live patient use, require:

1. healthcare counsel/compliance review for the exact US scope;
2. approved PHI data map and vendor/BAA chain;
3. threat model, role/access model, audit and incident procedures;
4. tested backup/restore and staff-offboarding behavior;
5. safe notification and patient identity behavior;
6. migration and rollback rehearsals using synthetic data;
7. a written boundary describing what Uplift is and is not the medical record of;
8. clinic acceptance testing with no live patient data until the gate passes.

### Near-term revenue if replacement is not ready

Jafar can still sell a recurring **website + conversion + clinic operations service** around the existing Boulevard integration: website maintenance, service/catalog updates, booking-flow setup, analytics, content, and operational onboarding. That does not capture Boulevard's full subscription and should not be presented as Uplift owning the patient system, but it monetizes the relationship while Uplift learns the market safely.

## 7. Decision

The new evidence changes the recommended **priority of discovery**, not the standard of product quality.

- Previous broad idea: build a salon/medspa/healthcare edition because the markets seem adjacent.
- Evidence-led direction: investigate a **cash-pay preventive/wellness clinic edition first**, because two reachable prospects exist and LifeScan's public workflow is concrete.
- Still wrong: clone all Boulevard features now, reuse contractor jobs as medical appointments, or hide menus and call the result compliant.
- Best move: preserve the contractor promise, start a tightly scoped paid clinic design-partner track now, and make the clinic replacement decision only after workflow, willingness-to-pay, and compliance gates are real.

Two warm prospects are valuable. They are enough to justify serious discovery and perhaps a paid pilot. They are not yet enough to justify building a general healthcare platform.

## Source list

All sources accessed 2026-10-05.

### LifeScan first-party pages

- [Home / public booking entry](https://lifescanhealthwellness.com/)
- [About](https://lifescanhealthwellness.com/about/)
- [Services](https://lifescanhealthwellness.com/services/)
- [Diagnostic services](https://lifescanhealthwellness.com/diagnostic/)
- [Privacy policy](https://lifescanhealthwellness.com/privacy-policy/)
- [Terms of service](https://lifescanhealthwellness.com/terms-of-service/)

### Boulevard first-party material

- [Client booking experience](https://support.boulevard.io/en/articles/5941525-the-client-booking-experience)
- [Client notifications](https://support.boulevard.io/en/articles/8447955-client-notifications)
- [Cancellation policies and fees](https://support.boulevard.io/en/articles/5941349-cancellation-policies-and-fees)
- [Forms and charts](https://support.boulevard.io/en/articles/6989798-forms-and-charts-building-forms-and-charts)
- [Client portal](https://support.boulevard.io/en/articles/8648439-client-portal)
- [Medspa add-on](https://support.boulevard.io/en/articles/9084775-medspa-add-on)
- [PHI security requirements](https://support.boulevard.io/en/articles/8550292-protected-health-information-phi-security-requirements)
- [Boulevard data security](https://www.joinblvd.com/features/data-security)
