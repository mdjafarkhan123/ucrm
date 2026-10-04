# B9 — Texting registration and protected documents

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` §3.6, §9; blueprint stage 9 and "Porting or hosted-number access"
**Code:** `main`
**Done when:** Document visible only to the owner and Jafar

## Steps

- [x] Read blueprint, plan, B8 migration, setup file code (`src/lib/server/setup/files.ts`)
- [x] Research: Twilio Port In API emails an e-sign transfer letter to the approver; carrier transfer PINs expire in 4–7 days (AT&T 4, Verizon/T-Mobile 7); Stripe keeps identity-document uploads non-downloadable
- [ ] Jafar answers the protected-document questions (below)
- [ ] Build protected document kind (storage, access, audit, retention) per his answers
- [ ] Write stage 9 migration with `private.setup_load_starter_stage`, test, apply to dev

## Next

Wait for Jafar's answers to Q1–Q5, then plan the protected-document build.

## Notes

Fact: setup files today are ordinary File library Files (role `setup_answer`); anyone with `files.view` can
browse them, so protected documents cannot reuse that path as is. Malware scanning (`src/lib/server/files/scanner.ts`) can be reused.

Questions waiting for Jafar (asked 2026-10-04):
Q1 Who can open a protected document? Recommended: owner and Jafar; admins can upload and see "received" but not open; never in the File library.
Q2 Transfer PIN: not asked in setup (it expires in days); asked in a one-time protected step when Uplift submits the move. Recommended.
Q3 Signed transfer letter: no upload; the phone provider emails it to B8's approver to sign online. Recommended.
Q4 Keep documents how long? Recommended: deleted 90 days after the registration or move it was for is finished; Jafar can delete sooner.
Q5 Access history: every upload, open and removal recorded; owner and Jafar can both see it. Recommended.
