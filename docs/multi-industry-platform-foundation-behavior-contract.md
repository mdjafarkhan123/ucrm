# Multi-industry platform foundation

**Status:** Planning. Product direction agreed by Jafar on 2026-10-08; P2 and P3 behavior approved on 2026-10-09. Contractor migration, build parts and implementation remain unapproved.

## Summary

Uplift will be one operating platform for supported local service businesses, not a white-label product and not a collection of copied applications. Contractor is the first Industry experience. Medspa & Clinical Wellness is second because prospective clinical customers exist and its stricter appointment, record and safety needs will establish the reusable appointment-business foundation. Beauty & Spa follows by reusing suitable appointment capabilities without inheriting clinical behavior.

The public Uplift journey, the private Uplift Control Room, each organization's Business Workspace, and its customer-facing surfaces are connected parts of one product. An organization's Industry experience decides its language and operating workflows; its Package edition decides what it purchased; each Team member's permissions decide what that person may do. Existing application work is audited and reused where it fits. The campaign will establish this platform shape, migrate Contractor onto it without losing history or access, prove the complete Contractor journey, and only then resume Medspa implementation.

## Product boundary and expansion method

- Uplift serves supported **local service businesses**. It does not claim that one generic CRM deeply operates every kind of business.
- A new Industry experience enters the product only after mature products and the industry's real workflows are researched, existing capabilities are checked for suitability, necessary specialist behavior is planned, and one connected journey has observable completion checks.
- Shared behavior is defined once. Configuration supplies safe defaults where the meaning is unchanged. A specialist module is added when an industry's records, rules, permissions, safety or money behavior materially differs.
- Existing work is classified as **keep**, **deepen into shared platform behavior**, **make experience-specific**, **replace**, or **retire**. File age or Contractor wording alone is not a reason to rebuild it.

## Product surfaces

1. **Public Uplift experience:** marketing, Packages and the Application through which a business asks to become an Uplift customer.
2. **Uplift Control Room:** the protected `/jafar` workspace where Jafar and authorized Uplift teammates run Business Management and Platform Operations. It is not a role inside a customer organization.
3. **Business Workspace:** the signed-in workspace used by an organization's Team members. It presents the organization's Industry experience rather than a generic collection of every Uplift tool.
4. **Customer-facing surface:** the permitted portal, request, booking, form, payment and communication journeys used by that organization's own customers.

Shared platform capabilities beneath these surfaces include organizations, identity, Packages, permissions, communication, payments, Files, audit history, Setup, automation and platform security. Their suitability for another Industry experience must still be verified.

## Business admission and launch journey

**P2 direction:** Jafar confirmed on 2026-10-09 that Uplift should follow the researched industry patterns for admission and public launch. The offsite payment process and private preparation during paid Setup are Uplift-specific decisions he already approved. The rules below are product behavior, not a claim that Boulevard uses Uplift's exact records or states.

The intended connected journey is:

> Lead when applicable → Application → Uplift qualification → Industry experience and Business type → compatible Package edition → confirmed offsite payment → Organization provisioning and administrator invitation → Setup → Uplift readiness review → permitted public launch → continuing support and commercial control

- Uplift explicitly confirms the Industry experience and Business type; service names never silently decide them.
- An Application never creates a tenant account by itself. Existing paid-prospect provisioning and immutable Package-edition history remain foundations.
- Confirmed payment may create the Organization and allow its administrator to enter Setup. It does not by itself claim that public requests, booking, treatment or another operating journey is ready.
- Commercial access, administrator readiness, Setup progress, operational readiness and public launch are separate facts. A stricter experience may require more readiness checks without forcing every Contractor through clinical rules.
- Unsupported or unclear businesses wait for a deliberate decision rather than receiving the closest-looking experience.

### Application and qualification

- The shared Application asks for the business and contact facts needed to reach its buyer, its location and time zone, the work it actually offers, and its proposed primary Business type. A clinical or mixed-service answer asks for the services involved, the US state, and who performs or supervises them. Marketing links may prefill a proposed type or Package, but the applicant can correct it; a link never settles classification.
- The applicant can compare Packages suitable for its stated work and record a preferred published edition. That choice is a preserved Application snapshot, not an entitlement or a promise that the business is supported. Uplift reviews the actual services and confirms the Industry experience, Business type and compatible edition before requesting payment. If the reviewed offer differs from the submitted choice, Uplift explains the change to the buyer and records the agreed edition before payment.
- An unclear or unsupported Application remains a platform-owned prospect under human review. The buyer sees what Uplift is checking and how to provide a missing fact. Uplift does not request payment or provision an Organization until it records a supported decision. If Uplift cannot serve the business, it marks the Application Not proceeding with a reason and tells the buyer plainly. A service name, trade text or Package choice never assigns an experience by itself.
- Confirmed regulated clinical work in a mixed business uses Medspa & Clinical Wellness as the primary experience, subject to its safeguards and state review. When the clinical boundary is uncertain, qualification waits for evidence. These rules carry forward the approved [Medspa entry decision](boulevard-product-behavior-contract.md#business-entry-and-onboarding).

### Organization experience profile

- Provisioning requires an owner-confirmed **experience profile**: primary Industry experience, Business type, reviewed service shape, compatible Agreement, decision owner, date and reason. It is visible in the Uplift Control Room. The Business Workspace shows its experience and relevant Setup path without exposing private qualification notes. The Application's original claims and any corrections remain in history; a correction does not rewrite what the buyer submitted or paid for.
- A later primary-experience change is an assisted transition of the same Organization. The Platform Owner reviews its records, Agreement, staff access, unfinished Setup, live customer-facing surfaces and any clinical safeguards, then records an effective-dated decision and impact. An unsupported transition stays on hold with the existing experience and access intact. Existing history retains its original meaning and access rules. The [Medspa entry decision](boulevard-product-behavior-contract.md#business-entry-and-onboarding) governs mixed and clinical transitions.

### Access, readiness and launch

| Fact | Who establishes it | Meaning and allowed actions |
| --- | --- | --- |
| Commercial access | Uplift confirms offsite payment and provisions the agreed Organization | Purchased internal capabilities may be used, subject to membership and permissions. This does not prove the initial administrator has accepted access or any operating workflow is ready. |
| Administrator readiness | The invited administrator securely completes access | The administrator can enter the Business Workspace and Setup. Failed invitation delivery is a recoverable access task, not a reason to create another Organization. |
| Setup progress | The business supplies answers; Uplift reviews the assigned program | Team members can prepare private records and configuration permitted by their Package and role. Setup completion or Ready for Uplift starts delivery work; neither opens a customer-facing journey. |
| Operational readiness | Uplift reviews the checks for a named workflow, with the business supplying required facts and approvals | A workflow can be used for real customer operations only when its applicable configuration, provider and safety checks pass. Another workflow may still wait. Clinical work needs its own safeguards and first-clinic review. |
| Public launch | Uplift releases an approved customer-facing surface after its relevant operational checks and required business approval | Customers may start the released request, booking, form or other journey. A different surface remains closed until its own checks and release pass. Publication/configuration alone is insufficient. |

- Jafar approved private preparation during paid Setup on 2026-10-09. The normal workspace and purchased tools remain available for that work; a blocked real-world action explains the missing check and who can resolve it. New customer intake, public booking, business-originating customer automation and clinical treatment must wait for their respective readiness and launch gates. Administrator invitations, Uplift Setup notices, support, required security messages and reconciliation continue under their own rules.
- The existing Contractor preview and customer approval remain part of delivery. Releasing a public surface requires the applicable approval plus that surface's checks. Uplift records **Mark as live** after the approved system actually launches, as the Contractor delivery contract requires. One live surface does not certify every other surface. An active lifecycle status, an enabled form or a published booking page never grants public use on its own.
- Existing customer commitments and recovery paths need a separate migration review before any new gate is enforced on live Contractor organizations. P4 must identify which public links, replies, payment/reconciliation actions and automations must continue while a surface is held, rather than treating every customer-facing action as new launch traffic.

## Experience composition

- **Shared platform:** organizations, identity, Packages, permissions, communication, Files, audit, support and other behavior whose meaning is truly common.
- **Field-service foundation:** Contractor requests, assessments, Quotes, Jobs, Visits and related field operations.
- **Appointment-business foundation:** services, staff and resource availability, Appointments, booking policies, deposits, checkout, rebooking and suitable paid benefits.
- **Clinical extension:** protected intake, consent, clearance, charts, clinical photos, review and clinical access history.

Contractor uses the field-service foundation. Medspa & Clinical Wellness uses the appointment-business foundation plus the clinical extension. Beauty & Spa later uses the appointment-business foundation without receiving clinical capabilities merely because both industries schedule services.

### Capability boundary

**P3 decision:** Jafar approved the rules in this section on 2026-10-09 after asking that they follow leading industry products. Boulevard's published Medspa add-on and granular permissions are the specialist reference; HighLevel's documented multi-industry packages inform reuse of common capabilities; OWASP's authorization guidance informs direct-access enforcement. The rules below are Uplift product choices, not a claim that these vendors use this exact internal design.

The experience definition lists **eligible** capability families, supported customer-facing journeys and safe defaults. A Package edition chooses which eligible commercial capabilities the business has bought. A person's permissions then narrow their access. Operational readiness and public release are further gates on real-world actions; neither a Package nor a role can bypass them. The resolved answer is shared by navigation, page loads, APIs, background actions and customer-facing entry points. An unknown experience, missing profile, unknown capability or unclassified permission fails closed and leaves existing history available through a reviewed recovery path.

| Family | Common meaning and reuse | Eligibility and boundary |
| --- | --- | --- |
| Shared platform | Organization, membership, commercial Agreement, Uplift support, contact identity, business-facing communication transport, Files infrastructure and audit machinery remain one platform. | Contractor and Medspa use the same foundations, but a shared engine does not make all its records visible. A contact's ordinary details and marketing consent are distinct from protected clinical details. Message templates, recipients, attachment access and automation triggers need experience-specific suitability checks. |
| Field service | Requests, assessments, Quotes, Jobs, Visits, field schedule and contractor invoice journeys retain their current meaning. | Contractor only. An appointment is not a renamed Visit, an appointment sale is not a contractor Invoice, and a clinical service is not a Job. |
| Appointment business | Service catalogue, provider/resource availability, appointment lifecycle, booking policies, deposits, checkout, rebooking and applicable paid benefits share one appointment model. | Medspa first; Beauty & Spa becomes eligible after its own planning and proof. The existing Contractor schedule and booking forms are reuse candidates for infrastructure, not evidence this family is built. |
| Clinical extension | Person-specific intake, consent, clearance, chart, clinical photo, review, protected access history and clinical safety gates. | Medspa only, for a reviewed service and authorized clinical staff. Package changes cannot remove required safety controls for a clinical workflow already in use. Beauty & Spa and Contractor never receive these records through generic customer or file permissions. |

One primary experience governs a business. Business type adjusts approved copy, Setup branches, initial settings and workflow defaults **within** that experience; it cannot add a capability or relax a safety rule. A mixed business may offer supplemental services only when the primary experience definition explicitly supports their workflow, record and permission model. Confirmed clinical services keep Medspa primary and keep clinical safeguards. An unsupported combination remains under Uplift review instead of being assembled from attractive menu items.

### Experience definition and presentation

Each supported experience has a reviewable, versioned definition: identifier and supported Business types; eligible families and commercial capability keys; required safety controls; terminology; primary navigation and dashboard modules; default settings; Setup program selection; supported public surfaces; and the readiness checks those surfaces require. Contractor's existing shell, labels and Setup questions are the first Contractor definition. Medspa receives its own appointment-led shell and clinical access rules. Beauty & Spa is not selectable until its definition and journeys have been planned and verified.

The definition supplies starting values, not an editable copy per Organization. A published change states which organizations it affects and is reviewed for record, permission, Setup and customer-facing impact before rollout. A started Setup program remains on its own version under the approved Setup rule. Day-to-day experience changes do not silently rewrite an Agreement, historical records or previously released public surfaces.

- **Contractor example:** a field member whose Package includes Jobs and Scheduling and whose role permits assigned Jobs sees the relevant schedule and assigned work. They cannot reach appointments or charts by a copied URL. A Contractor Package can omit a field feature only under the existing package-dependency and hidden-feature rules.
- **Medspa example:** a front desk member may see appointment times and a booking requirement warning when their Package includes scheduling and their role allows it. That does not grant chart, photo, medication or clearance access. A treating clinician needs separately granted clinical rights and a service's readiness checks still govern starting treatment. Contractor Quotes and Jobs stay absent from the Medspa menu and direct routes.
- **Mixed Medspa example:** a clinic also offering ordinary facials may use supported nonclinical services in its appointment catalogue. Its clinical records remain protected and regulated treatments retain clinical checks; a facial service does not downgrade the whole Organization to Beauty & Spa.

### Package and permission rules

- A published Package edition declares which supported experiences may buy it. It may serve more than one experience only if **every** included software capability, promised managed service, highlight, allowance and dependency has valid meaning and delivery for each one. Experience-neutral branding is insufficient. The builder previews compatibility and refuses publication of a broken combination; a published edition's eligibility and promises are fixed with that edition. A later edition can have a different audience without moving existing Agreements.
- Public comparison and Application selection show only editions compatible with the proposed Industry experience and Business type, while making clear that Uplift will confirm classification. Uplift review checks the final profile and every purchased capability again before requesting payment and provisioning. An old link or corrected classification that changes eligibility requires an explained new edition and buyer agreement; it never silently drops an included item.
- Temporary capability exceptions and later Package moves may grant only a capability eligible for the Organization's confirmed experience, with its dependencies and readiness met. Removing a capability keeps its historical records under the existing downgrade rules and stops new dependent actions. Safety controls such as clinical audit, clearance and consent are mandatory parts of supported clinical operation, not optional upsells or overrideable extras.
- Effective access is the intersection of Organization membership and status, confirmed experience eligibility, current Package edition plus valid exceptions, and the member's explicit role/individual permissions. A permission never manufactures an absent entitlement. Clinical record read, chart edit, clearance, sign-off, bypass, export and access administration remain separate; owner, administrator and job title do not automatically imply clinical visibility. Record-level subject/scope and clinical safety rules narrow access further.
- Navigation and dashboard modules come from that same effective answer, so unavailable capabilities leave no trace in a business's normal workspace. Direct URLs, API reads and writes, database policies, background work, exports, Files, search and customer-facing tokens enforce the equivalent boundary. A refusal identifies the relevant cause without leaking protected record existence. Uplift Control Room access remains a separate platform-team grant, never an Organization role.
- Readiness is checked at the action or public surface it protects. Staff can prepare permitted private work during paid Setup; real customer intake, public booking, business-originating automation and treatment wait for their own gates. Existing customer links, replies and payment recovery during a hold require the preservation review in P4.

## Experience, Package and permission controls

- The **Industry experience** controls operating language, primary navigation, workflows, applicable capability families, Setup program and safety posture.
- The **Business type** refines defaults within that experience without creating another product.
- The **Package edition** records the capabilities, allowances, included services and commercial terms the organization agreed to.
- **Team-member permissions** narrow what an authorized person may view or change; they never create a capability the Industry experience or Package does not allow.
- Uplift must refuse incompatible combinations before publication or assignment. Hidden navigation is not enforcement: direct reads and writes follow the same resolved access.
- Each experience needs a versioned, reviewable definition of its navigation, terminology, defaults, Setup program and supported customer-facing surfaces. The technical shape of that definition is decided after the current application audit.

## Preservation and proof

- Existing organizations move to the Contractor Industry experience with their records, Agreement, permissions, history and working behavior preserved. Missing historical facts are not invented.
- The current Contractor journey is proven end to end after the foundation changes: Application, review, payment confirmation, provisioning, invitation, Setup, Business Workspace, a real Contractor workflow, support and commercial recovery.
- Medspa implementation waits until the platform foundation and Contractor migration are proven. Existing Boulevard research and approved behavior remain valid inputs; they are not discarded or treated as built.
- Capacity, readiness and regulatory claims require their own evidence. A configurable architecture does not establish them.

### P4 Contractor migration proposal — awaiting Jafar's approval

The [P4 audit](research/multi-industry-contractor-migration-audit-2026-10-09.md) found existing Organizations and published forms but no stored Industry experience, Business type or universal launch record. Before any migration, Uplift repeats a per-Organization inventory of identity, commercial terms, staff grants, Contractor work and links, Setup/delivery records, provider configuration, public surfaces and background senders. The owner reviews which Organizations really remain Contractor. A missing Business type stays unknown; free-text trade does not fill it in.

Migration adds a reviewed Contractor experience profile without changing Organization IDs, Agreements, Package editions, lifecycle status or existing work records. It compares the old and new access answers for actual Packages and roles before switching an Organization. Any unexplained loss or gain stops that Organization's cutover. A test Organization goes first, followed by reviewed existing Organizations in small cohorts. The previous Contractor access path remains available for a controlled recovery until the new path and customer links pass proof; rollback does not delete a profile or rewrite customer history.

**Proposed continuity rule:** an active Contractor form already enabled and published may keep accepting requests while its Organization remains on the old Contractor path, unless Uplift finds a security or business-safety problem. Uplift reviews each existing form before that Organization's cutover and records whether it may continue under the new public-release gate. New or materially changed forms wait for their own release. Already issued quote, invoice, visit, report, review and File links, customer replies, and payment/reconciliation actions keep their existing expiry, revocation and security rules while Uplift checks the applicable journey; a general Setup hold does not automatically cancel those obligations. Business-originating automation that starts new customer work follows its own readiness check.

Contractor proof follows one connected Application-to-payment-to-Setup-to-Request-to-Quote-to-Job/Visit-to-Invoice/payment journey, then support and commercial recovery. It also checks an existing Organization's historical records and issued customer links, role-limited menu and direct access, closed new public surfaces, and refusal of Medspa/clinical access. The migration stops before Medspa implementation if preserved facts, access comparison, customer actions or recovery cannot be demonstrated.

## Still unclear

- The complete audit of current Control Room, provisioning, Package, Setup, access, shell, routes and data behavior against this plan.
- Jafar's approval of the P4 Contractor migration, existing-form continuity and connected-proof proposal above.

## Not doing

- White-label or reseller branding — businesses use Uplift as the product.
- A second application or copied database for Medspa — Industry experiences live in one platform.
- A ground-up rewrite — existing behavior is retained unless the audit shows why it cannot serve the agreed model.
- A promise to support every industry — only researched and verified Industry experiences are offered.
- Combining Medspa & Clinical Wellness with Beauty & Spa — they share appointment capabilities but retain different operating and safety rules.
- New Medspa implementation before the foundation and Contractor proof — research remains available while code waits for the shared shape.

## Sources and related plans

- [P1 current-state journey audit](research/multi-industry-current-state-audit-2026-10-09.md)
- [Admission, readiness and launch research](research/multi-industry-admission-readiness-2026-10-09.md)
- [P3 experience composition and access research](research/multi-industry-experience-access-2026-10-09.md)
- [P4 Contractor migration and connected-proof audit](research/multi-industry-contractor-migration-audit-2026-10-09.md)
- [Platform overview](platform-overview.md)
- [Contractor blueprint](PRODUCT.md)
- [Jafar Business Management](jafar-business-management-behavior-contract.md)
- [Platform Owner organization-management mission](jafar-organization-management-mission.md)
- [Client onboarding and delivery](client-onboarding-delivery-behavior-contract.md)
- [Package builder](package-builder-behavior-contract.md)
- [Paid-prospect provisioning decision](adr/0001-paid-prospect-provisioning-and-versioned-packages.md)
- [Boulevard-inspired Industry experiences](boulevard-product-behavior-contract.md)
- [HighLevel multi-industry research](research/highlevel-multi-industry-white-label-architecture-2026-10-08.md)
- [Industry entry research](research/industry-onboarding-entry-patterns-2026-10-07.md)
