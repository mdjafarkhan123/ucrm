# Multi-industry platform foundation

**Status:** Planning. Product direction agreed by Jafar on 2026-10-08; detailed behavior, build parts and implementation remain unapproved.

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

The intended connected journey is:

> Lead when applicable → Application → Uplift qualification → Industry experience and Business type → compatible Package edition → confirmed offsite payment → Organization provisioning and administrator invitation → Setup → Uplift readiness review → permitted public launch → continuing support and commercial control

- Uplift explicitly confirms the Industry experience and Business type; service names never silently decide them.
- An Application never creates a tenant account by itself. Existing paid-prospect provisioning and immutable Package-edition history remain foundations.
- Confirmed payment may create the Organization and allow its administrator to enter Setup. It does not by itself claim that public requests, booking, treatment or another operating journey is ready.
- Commercial access, administrator readiness, Setup progress, operational readiness and public launch are separate facts. A stricter experience may require more readiness checks without forcing every Contractor through clinical rules.
- Unsupported or unclear businesses wait for a deliberate decision rather than receiving the closest-looking experience.

## Experience composition

- **Shared platform:** organizations, identity, Packages, permissions, communication, Files, audit, support and other behavior whose meaning is truly common.
- **Field-service foundation:** Contractor requests, assessments, Quotes, Jobs, Visits and related field operations.
- **Appointment-business foundation:** services, staff and resource availability, Appointments, booking policies, deposits, checkout, rebooking and suitable paid benefits.
- **Clinical extension:** protected intake, consent, clearance, charts, clinical photos, review and clinical access history.

Contractor uses the field-service foundation. Medspa & Clinical Wellness uses the appointment-business foundation plus the clinical extension. Beauty & Spa later uses the appointment-business foundation without receiving clinical capabilities merely because both industries schedule services.

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

## Still unclear

- Which facts the public Application collects before Uplift can identify a supported Industry experience and Business type, and how correction or an unresolved classification works.
- The exact Organization experience profile, its history, and the assisted rules for changing an existing organization's primary experience.
- The compatibility rules among Industry experience, Business type, Package capabilities, additional capabilities and mixed-service businesses.
- The exact readiness states, responsible people, visible explanations, and which public or staff actions each state permits.
- The experience definition's product behavior: navigation, dashboard, terminology, defaults, Setup selection and customer-facing surfaces.
- The complete audit of current Control Room, provisioning, Package, Setup, access, shell, routes and data behavior against this plan.
- The safe Contractor backfill, rollout, rollback and connected proof required before Medspa implementation resumes.

## Not doing

- White-label or reseller branding — businesses use Uplift as the product.
- A second application or copied database for Medspa — Industry experiences live in one platform.
- A ground-up rewrite — existing behavior is retained unless the audit shows why it cannot serve the agreed model.
- A promise to support every industry — only researched and verified Industry experiences are offered.
- Combining Medspa & Clinical Wellness with Beauty & Spa — they share appointment capabilities but retain different operating and safety rules.
- New Medspa implementation before the foundation and Contractor proof — research remains available while code waits for the shared shape.

## Sources and related plans

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
