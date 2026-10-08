# Platform overview

**Status:** Direction agreed 2026-10-05 and multi-industry foundation direction confirmed 2026-10-08. Medspa & Clinical Wellness first-release behavior and build order are approved, but implementation waits for the shared platform foundation and connected Contractor proof. Delivery and first-clinic readiness remain unverified; Beauty & Spa details follow later.

## Product direction

One platform serves different business types through focused industry experiences. The existing contractor edition follows Jobber. The next expansion follows Boulevard, prioritizing Medspa & Clinical Wellness together with the shared capabilities it needs; Beauty & Spa follows. This is a commercial product for a market, not a custom application for LifeScan.

The business account determines the industry experience; subscription features and staff permissions further determine access. Relevant terminology, navigation, workflows, forms, and reports should fit that business. Access must be enforced beyond hiding controls. A separate product copy is not created for each customer. Mixed-service businesses need an explicitly planned combination of capabilities.

Uplift is the visible product, not a white-label reseller system. The protected `/jafar` workspace is the **Uplift Control Room**; an organization's signed-in staff use its **Business Workspace**; and that organization's own customers use permitted request, booking, portal, form, payment and communication surfaces. Confirmed payment may open Setup access, while operational readiness and public launch remain separate facts. Existing behavior is audited for reuse before it is changed.

## Sources of truth

- [Contractor blueprint](PRODUCT.md): existing contractor behavior and links to its detailed contracts.
- [Multi-industry platform foundation](multi-industry-platform-foundation-behavior-contract.md): the agreed platform direction and the decisions still required before implementation.
- [Boulevard product plan](boulevard-product-behavior-contract.md): approved Medspa behavior, release boundary, research gaps and first-clinic gates.
- [Approved build order](research/boulevard-p4-review-proposal-2026-10-08.md): sequence to split into focused parts before implementation.

## Planning method

Work from product vision → business types → capability areas → features → workflows and rules → completion checks. Describe shared behavior once, then record industry differences. Review complete booking-to-follow-up journeys to catch gaps between features.

### Reference order and missing behavior

1. Research Boulevard first using official public help, training, demonstrations, release notes, and developer documentation. No subscription is available for a live tour.
2. When a necessary feature or behavior remains undocumented, unclear, or unavailable in Boulevard, research a relevant established competitor's official sources. Vagaro is a starting comparison for beauty, wellness and medspa workflows; choose another specialist when its workflow is a better match.
3. Record the gap, the competitor and source, the behavior proposed for our product, and why it fits. Label it as competitor-derived rather than confirmed Boulevard behavior. Missing documentation does not prove Boulevard lacks the feature.
4. Keep the result consistent with our agreed workflows. Put meaningful trade-offs or changes to approved scope to Jafar with a recommendation. A competitor feature does not automatically enter the initial release.
5. If reliable evidence is still missing, retain an open question or explicitly proposed behavior; do not invent a vendor rule.

Public research cannot establish undocumented interactions or a competitor's private architecture.

Inventory the full documented feature landscape before selecting initial versus later releases. Include add-ons, integrations, and availability restrictions. Existing inbox, marketing, automation, permissions, customer and financial work must be assessed for reuse and suitability; existence does not establish readiness for a new industry.

## Quality and scope

Each release must support complete agreed workflows with observable completion checks. Keep research confidence, release assignment, and delivery status separate. Capacity and reliability claims require measured evidence for the relevant workload; no promise of unlimited scale or zero slowdown follows from choosing a design.

Keep existing contractor work and infrastructure rules in force. The approved plan records behavior and build order; it does not establish application, provider, infrastructure or clinic readiness. Jafar approved US first, single-location teams first, and Boulevard-style clinical/business workflows with specialist diagnostic test/report systems outside the initial promise on 2026-10-05. The 2026-10-08 first-release map assigns inventory families; clinic-dependent capabilities are selected from the actual first clinic's needs before go-live.
