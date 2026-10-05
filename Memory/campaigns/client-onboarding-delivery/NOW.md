# Client onboarding and delivery — now

**Goal:** A paid contractor can complete one plain-language setup, use the full CRM immediately, follow Uplift's
7–10-business-day delivery, approve launch, receive training, and contact Uplift throughout.
**Plan:** `docs/client-onboarding-delivery-behavior-contract.md`

**In progress:** A5 is built and still waits for Jafar's hands-on publish (part note), which also gives A5b–A5g their live client-side look.

**Also waiting on Jafar's publish:** B9c's login check (part note `parts/B9-texting-facts.md`); the stage itself is built.

**Next part:** C5 Fill CRM settings (`stages/C-review.md`, plan §4, §10 journey 6). Accepted values come from
`readSectionReviews` (`$lib/server/setup/client-page.ts`); a help question's accepted value is Uplift's answer
(`$lib/setup/help.ts`). Raad LTD's "Your business" is accepted on send 1, not Ready, and its public phone has a
test Uplift answer (dev data). Do NOT publish test
stages or questions on dev; stage keys are never reused.

**Blockers:** none for C2. Text limits max 2000. A reused question must point to one with no "show only if" rule (the database refuses otherwise).
