# B9 — Texting registration and protected documents

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` §3.6, §9; blueprint stage 9 and "Porting or hosted-number access"
**Code:** `main`
**Done when:** Document visible only to the owner and Jafar

## Steps

- [x] Read blueprint, plan, B8 migration, setup file code (`src/lib/server/setup/files.ts`)
- [x] Research: Twilio Port In API emails an e-sign transfer letter to the approver; carrier transfer PINs expire in 4–7 days (AT&T 4, Verizon/T-Mobile 7); Stripe keeps identity-document uploads non-downloadable
- [x] Jafar answered the protected-document questions (below)
- [ ] Build protected document kind (storage, access, audit, retention) per his answers
- [ ] Write stage 9 migration with `private.setup_load_starter_stage`, test, apply to dev

## Next

Plan the protected-document build (storage, access, audit, deletion date) against the existing setup upload path.

## Outside actions

- Apply migration `20261018090000_setup_protected_documents` to dev — check: `select 1 from supabase_migrations.schema_migrations where version = '20261018090000'` — pending

## Notes

Fact: setup files today are ordinary File library Files (role `setup_answer`); anyone with `files.view` can
browse them, so protected documents cannot reuse that path as is. Malware scanning (`src/lib/server/files/scanner.ts`) can be reused.

Jafar's decisions (2026-10-04, after comparing with GoHighLevel's port-in and A2P flow):
1. Only the owner and Jafar can open a protected document; an admin can upload it and sees "received"; never in the File library.
2. No transfer PIN in setup; a one-time protected step asks for it when Uplift submits the move (as GHL does).
3. No signed-letter upload; Twilio emails the letter to B8's approver to sign online.
4. Deleted automatically 90 days after the registration or move it served is finished; Jafar can delete sooner.
5. Every upload, open and removal is recorded; owner and Jafar both see the list.
6. A US client may optionally upload the IRS CP-575 tax letter (protected) instead of only typing; never required.
