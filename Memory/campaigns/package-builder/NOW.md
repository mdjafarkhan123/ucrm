# Package builder — now

**Goal:** Jafar can build configurable packages and manually assign published editions that preserve each customer's features, limits, and price.
**Plan:** `docs/package-builder-behavior-contract.md` · **Technical approach:** `docs/adr/0003-package-editions-agreements-and-offsite-billing-ledger.md`

**Completed:** Planning (P1, P2). Jafar approved the build parts on 2026-09-29.

**Next part:** P3 Switch to the new package storage (`stages/1-foundation.md`). It is the largest and riskiest part; start it in a fresh session and split it if it outgrows one.

**Blockers:** None.

Jafar approved rebuilding the whole package system while keeping each feature's existing access check, and clearing the four test organizations' old package and payment history. All organizations are fake. Live test data on 2026-09-29: Raad LTD and Jaaroweb are on Elite v2, Riverside on Starter v3, and xdasd is legacy with no assignment; all seven onboarding applications point at old versions. The shared inbox (`conversations.*`) has no package lock today. Coordinate the Jafar panel's final audit (its Part 11) with this campaign's P15.
