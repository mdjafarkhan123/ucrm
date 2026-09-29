# Package builder — now

**Goal:** Jafar can build configurable packages and manually assign published editions that preserve each customer's features, limits, and price.
**Plan:** `docs/package-builder-behavior-contract.md` · **Technical approach:** `docs/adr/0003-package-editions-agreements-and-offsite-billing-ledger.md`

**Completed:** Planning (P1, P2). Jafar approved the build parts on 2026-09-29.

**Next part:** P3c Database tests on package editions, then P4 (`stages/1-foundation.md`). P3b done 2026-09-30.

**Blockers:** None.

Jafar approved rebuilding the whole package system while keeping each feature's existing access check, and clearing the four test organizations' old package and payment history. All organizations are fake. All four organizations and all seven onboarding applications sit on the private test package's edition 1. The shared inbox (`conversations.*`) has no package lock today. Since P3b: the old package tables are gone; `/get-started` lists no packages until a public edition is published (P7); Raad LTD and Jaaroweb hold open-ended test free access until P5 rebuilds it; the old payment tables stay empty until P4; the prospect page's confirm-payment and activation buttons still answer "being rebuilt" until P10; the test edition leaves out only missed-call text-back; a SECURITY INVOKER function members call must not name anything in `private`. Coordinate the Jafar panel's final audit (its Part 11) with this campaign's P15.
