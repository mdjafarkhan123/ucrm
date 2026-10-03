# Client onboarding and delivery — now

**Goal:** A paid contractor can complete one plain-language setup, use the full CRM immediately, follow Uplift's
7–10-business-day delivery, approve launch, receive training, and contact Uplift throughout.
**Plan:** `docs/client-onboarding-delivery-behavior-contract.md`

**In progress:** nothing claimed. A3 (questions in the database) done 2026-10-03 — ADR 0006.

**Next part:** A4 stage editor in Jafar's panel: create a draft from the published version, add/rename/
reorder/remove stages, tie a stage to a service, publish (ADR 0006 §Consequences). The wizard must then hide
a stage whose `service_key` the client's edition's `included_services` lacks — the setup routes and
`owner_client_onboarding_list` both need that per-client filter. Then A5.
C2 onward waits for B13.

**Blockers:** none. Build order approved 2026-10-01.
