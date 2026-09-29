# Package builder — now

**Goal:** Jafar can build configurable packages and manually assign published editions that preserve each customer's features, limits, and price.
**Plan:** `docs/package-builder-behavior-contract.md` · **Technical approach:** `docs/adr/0003-package-editions-agreements-and-offsite-billing-ledger.md`

**Completed:** Planning (P1, P2). Jafar approved the build parts on 2026-09-29.

**Next part:** P3b Remove the old package storage (`stages/1-foundation.md`). P3a merged 2026-09-29.

**Blockers:** None.

Jafar approved rebuilding the whole package system while keeping each feature's existing access check, and clearing the four test organizations' old package and payment history. All organizations are fake. Live test data on 2026-09-29: Raad LTD and Jaaroweb are on Elite v2, Riverside on Starter v3, and xdasd is legacy with no assignment; all seven onboarding applications point at old versions. The shared inbox (`conversations.*`) has no package lock today. Since P3a: the old tables stay, unread, until P3b; free access still reads the old events until P5; the test edition leaves out only missed-call text-back; a SECURITY INVOKER function members call must not name anything in `private`. Coordinate the Jafar panel's final audit (its Part 11) with this campaign's P15.
