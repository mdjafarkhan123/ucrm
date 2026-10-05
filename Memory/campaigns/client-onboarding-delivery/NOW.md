# Client onboarding and delivery — now

**Goal:** A paid contractor can complete one plain-language setup, use the full CRM immediately, follow Uplift's
7–10-business-day delivery, approve launch, receive training, and contact Uplift throughout.
**Plan:** `docs/client-onboarding-delivery-behavior-contract.md`

**In progress:** A5 is built and still waits for Jafar's hands-on publish (part note), which also gives A5b–A5g their live client-side look.

**Also waiting on Jafar's publish:** B9c's login check (part note `parts/B9-texting-facts.md`); the stage itself is built.

**Next part:** E1 Status timeline (`stages/E-delivery.md`, plan §5). Stage C is done: accepting a task now
fills the client's CRM settings (C5, `$lib/server/setup/settings-copy.ts`). Raad LTD is accepted on "Your
business", not Ready (dev data). Do NOT publish test stages or questions on dev; stage keys are never reused.

**Blockers:** none for E1. Text limits max 2000. A reused question must point to one with no "show only if" rule (the database refuses otherwise).
