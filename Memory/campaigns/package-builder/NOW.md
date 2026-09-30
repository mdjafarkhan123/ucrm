# Package builder — now

**Goal:** Jafar can build configurable packages and manually assign published editions that preserve each customer's features, limits, and price.
**Plan:** `docs/package-builder-behavior-contract.md` · **Technical approach:** `docs/adr/0003-package-editions-agreements-and-offsite-billing-ledger.md`

**Completed:** Planning (P1, P2). Jafar approved the build parts on 2026-09-29.

**Next part:** P5b Contractor banner and paused screen (`stages/1-foundation.md`).

**Blockers:** None. **Asked Jafar 2026-09-30:** approve which billing actions ask for the password (`billingStepUpActions`)?

All organizations are fake. The shared inbox (`conversations.*`) has no package lock today. Since P3b: the old package tables are gone; `/get-started` lists no packages until a public edition is published (P7); Raad LTD and Jaaroweb hold test free access through 2027-09-30; a sweep every 15 minutes pauses organizations whose grace ended (`private.enforce_package_grace`), and P5b's banner must read `private.organization_access_coverage` through a SECURITY DEFINER wrapper; the old payment tables are gone (P4a); Jaaroweb holds test billing records from the P4b browser check; the prospect page's confirm-payment and activation buttons still answer "being rebuilt" until P10; the test edition leaves out only missed-call text-back; a SECURITY INVOKER function members call must not name anything in `private`. Database tests insert agreements and exceptions directly until owner commands exist. Coordinate the Jafar panel's final audit (its Part 11) with this campaign's P15.
