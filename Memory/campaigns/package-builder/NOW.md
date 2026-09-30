# Package builder — now

**Goal:** Jafar can build configurable packages and manually assign published editions that preserve each customer's features, limits, and price.
**Plan:** `docs/package-builder-behavior-contract.md` · **Technical approach:** `docs/adr/0003-package-editions-agreements-and-offsite-billing-ledger.md`

**Completed:** Stages 1–2; P8a–P10; P11a offer rules (database), 2026-09-30.

**Next part:** P11b offer screens (stage 3), paused mid-part — continue from `parts/P11b-offer-screens.md`. P12 is also ready.

**Waiting on Jafar:** (1) OK to add P10's four activation rules to the plan § Offsite payment and coverage: coverage starts on the business's local activation day; first payment must cover the first charge, the intro price when an offer applies (extra is credit); a prospect's package changes only before payment or after a reversal; activation uses the edition the customer agreed to. (2) Jaaroweb is still on Starter Check from the P8b check; restoring it needs his password on the Billing tab.

**Blockers:** None. Password-protected billing actions are Jafar's list in `billingStepUpActions` (2026-09-30).

The shared inbox (`conversations.*`) has no package lock today. Raad LTD and Jaaroweb hold test free access through 2027-09-30. A SECURITY INVOKER function members call must not name anything in `private`. Coordinate the Jafar panel's Part 11 audit with this campaign's P15.
