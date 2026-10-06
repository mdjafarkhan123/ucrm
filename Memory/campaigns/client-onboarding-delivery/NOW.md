# Client onboarding and delivery — now

**Goal:** A paid contractor can complete one plain-language setup, use the full CRM immediately, follow Uplift's
7–10-business-day delivery, approve launch, receive training, and contact Uplift throughout.
**Plan:** `docs/client-onboarding-delivery-behavior-contract.md`

**In progress:** A5 is built and still waits for Jafar's hands-on publish (part note), which also gives A5b–A5g their live client-side look.

**Also waiting on Jafar's publish:** B9c's login check (part note `parts/B9-texting-facts.md`); the stage itself is built.

**Next to build:** E6 Training + handover — Jafar approved all behavior on 2026-10-06 (`parts/E6-training-handover.md`); he asked to stop before coding and switch to Claude. It adds states 10–11
(Live — training next, Project delivered) to `$lib/setup/project-state.ts`. Raad LTD is accepted on "Your business", not Ready (dev data). Do NOT publish
test stages or questions on dev; stage keys are never reused.

**Blockers:** none for E1. Text limits max 2000. A reused question must point to one with no "show only if" rule (the database refuses otherwise).
