# Client onboarding and delivery — now

**Goal:** A paid contractor can complete one plain-language setup, use the full CRM immediately, follow Uplift's
7–10-business-day delivery, approve launch, receive training, and contact Uplift throughout.
**Plan:** `docs/client-onboarding-delivery-behavior-contract.md`

**In progress:** A5 is built and still waits for Jafar's hands-on publish (part note), which also gives A5b–A5g their live client-side look.

**Also waiting on Jafar's publish:** B9c's login check (part note `parts/B9-texting-facts.md`); the stage itself is built.

**Next part:** E3 Preview + correction is built and paused before its checks (`parts/E3-preview-corrections.md`); E1 and E2 are done. E1: the client's step tracker and
Jafar's list share `$lib/setup/project-state.ts`; states 8–11 still need E3–E6 to add their records there.
Raad LTD is accepted on "Your business", not Ready (dev data). Do NOT publish test stages or questions on dev;
stage keys are never reused.

**Blockers:** none for E1. Text limits max 2000. A reused question must point to one with no "show only if" rule (the database refuses otherwise).
