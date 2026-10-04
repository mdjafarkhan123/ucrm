# Client onboarding and delivery — now

**Goal:** A paid contractor can complete one plain-language setup, use the full CRM immediately, follow Uplift's
7–10-business-day delivery, approve launch, receive training, and contact Uplift throughout.
**Plan:** `docs/client-onboarding-delivery-behavior-contract.md`

**In progress:** A5 is built and still waits for Jafar's hands-on publish (part note), which also gives A5b–A5g their live client-side look.

**Also waiting on Jafar's publish:** B9c's login check (part note `parts/B9-texting-facts.md`); the stage itself is built.

**Next part:** C3c Uplift's to-do (`stages/C-review.md`, plan §4 decision 4). Builds on the Setup tab
(`/jafar/organizations/[id]?tab=setup`). Raad LTD's "Your business" is currently sent back on send 1 (dev test
data). Do NOT publish test stages or questions on dev; stage keys are never reused.

**Blockers:** none for C2. Text limits max 2000. A reused question must point to one with no "show only if" rule (the database refuses otherwise).
