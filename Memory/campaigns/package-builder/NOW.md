# Package builder — now

**Goal:** Jafar can build configurable packages and manually assign published editions that preserve each customer's features, limits, and price.
**Plan:** `docs/package-builder-behavior-contract.md` · **Technical approach:** `docs/adr/0003-package-editions-agreements-and-offsite-billing-ledger.md`

**Completed:** Stages 1–4, 2026-10-01. Automations is sellable.

**Next part:** P15 final check; it ends when Jafar publishes his two real packages.

**Waiting on Jafar:** Nothing. Jafar authorized whatever P15 needs (2026-10-01), including putting Jaaroweb back on its package: it is still on Starter Check from the P8b test, and the Billing tab asks for his `/jafar` password (in CLAUDE.md).

**Blockers:** None. Password-protected billing actions are Jafar's list in `billingStepUpActions` (2026-09-30).

The inbox lock is a feature check per route (`featureUnavailable` in `src/lib/server/access/permission.ts`), because `conversations.*` permissions also cover quote emails. Raad LTD and Jaaroweb hold test free access through 2027-09-30. A SECURITY INVOKER function members call must not name anything in `private`. Coordinate the Jafar panel's Part 11 audit with this campaign's P15.
