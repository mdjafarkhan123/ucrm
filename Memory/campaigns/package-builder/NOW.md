# Package builder — now

**Goal:** Jafar can build configurable packages and manually assign published editions that preserve each customer's features, limits, and price.
**Plan:** `docs/package-builder-behavior-contract.md` · **Technical approach:** `docs/adr/0003-package-editions-agreements-and-offsite-billing-ledger.md`

**Completed:** Planning (P1, P2); stage 1 Foundation (P3a–P5c); P6 drafts, 2026-09-30.

**Next part:** P7 Publish, archive, and restore (stage `stages/2-builder.md`). Draft commands: `supabase/migrations/20260930200000_package_drafts.sql`.

**Blockers:** None. **Asked Jafar 2026-09-30:** approve which billing actions ask for the password (`billingStepUpActions`)?

All organizations are fake. The shared inbox (`conversations.*`) has no package lock today. Since P3b: the old package tables are gone; `/get-started` lists no packages until a public edition is published (P7); Raad LTD and Jaaroweb hold test free access through 2027-09-30; Riverside Legacy Demo is in its grace week; a sweep every 15 minutes pauses organizations whose grace ended (`private.enforce_package_grace`); the app shell reads `public.contractor_account_standing` for the banner and paused screen; Jaaroweb holds test billing records from the P4b browser check; the prospect page's confirm-payment and activation buttons still answer "being rebuilt" until P10; the test edition leaves out only missed-call text-back; a SECURITY INVOKER function members call must not name anything in `private`. Coordinate the Jafar panel's final audit (its Part 11) with this campaign's P15.
