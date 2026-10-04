# Client onboarding and delivery — now

**Goal:** A paid contractor can complete one plain-language setup, use the full CRM immediately, follow Uplift's
7–10-business-day delivery, approve launch, receive training, and contact Uplift throughout.
**Plan:** `docs/client-onboarding-delivery-behavior-contract.md`

**In progress:** A5 is built and still waits for Jafar's hands-on publish (part note), which also gives A5b–A5g their live client-side look.

**Also waiting on Jafar's publish:** B9c's login check (part note `parts/B9-texting-facts.md`); the stage itself is built.

**Next part:** B13 Check and send (`stages/B-wizard.md`, plan §3.10, blueprint stage 12). Unlike B3b–B12 it is code, not loaded content: the system builds the summary.
Do NOT publish test stages or questions on dev; stage keys are never reused. C2 onward waits for B13.

**Blockers:** none for B13. Text limits max 2000. A reused question must point to one with no "show only if" rule (the database refuses otherwise).
