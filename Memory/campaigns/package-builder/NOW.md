# Package builder — now

**Goal:** Jafar can build configurable packages and manually assign published editions that preserve each customer's features, limits, and price.
**Plan:** `docs/package-builder-behavior-contract.md` · **Technical approach:** `docs/adr/0003-package-editions-agreements-and-offsite-billing-ledger.md`

**Completed:** Planning (P1, P2); stage 1 Foundation (P3a–P5c); P6 drafts and P7 publish/archive/restore (browser-checked), 2026-09-30. Stage 2 done.

**Next part:** Stage 3 customers (`stages/3-customers.md`): P8 change a customer's package, or P9 public package cards (both wait only on done work). P12 (stage 4) is also ready.

**Blockers:** None. **Decided by Jafar 2026-09-30:** keep the password list as built (`billingStepUpActions`): refund, void, correct payment, adjust paid-through, and free-access grant/extend/end. Everyday billing needs no password.

All organizations are fake. The shared inbox (`conversations.*`) has no package lock today. Since P3b: the old package tables are gone; `/get-started` lists no packages until a public edition is published (P7); Raad LTD and Jaaroweb hold test free access through 2027-09-30; Riverside Legacy Demo is in its grace week; a sweep every 15 minutes pauses organizations whose grace ended (`private.enforce_package_grace`); the app shell reads `public.contractor_account_standing` for the banner and paused screen; Jaaroweb holds test billing records from the P4b browser check; the prospect page's confirm-payment and activation buttons still answer "being rebuilt" until P10; the test edition leaves out only missed-call text-back; a SECURITY INVOKER function members call must not name anything in `private`. Coordinate the Jafar panel's final audit (its Part 11) with this campaign's P15.
