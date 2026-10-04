# B9b — Protected upload question (B9a done 2026-10-04)

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` §3.6, §9; blueprint stage 9 and "Porting or hosted-number access"
**Code:** `main`
**Done when:** Admin sees "received", cannot open; owner and Jafar can (in the browser)

## Steps

- [x] B9a store: migration `20261018090000` (on dev), pgTAP test, `src/lib/server/setup/protected-documents*.ts`, routes under `src/routes/api/setup/protected-documents/` and `api/jafar/organizations/[organizationId]/setup/protected-documents/`, answer-save check, worker tick
- [x] Editor: "Protected document" type; migration `20261019090000` (on dev) keeps its file limit and refuses reusing it
- [x] Setup page field: `SetupFilesField` `secure` mode, `ProtectedDocumentHistory` popover
- [x] Jafar's client page: new Setup tab (`SetupWorkspace.svelte`) on the organization page; list route `api/jafar/organizations/[organizationId]/setup/protected-documents`
- [ ] Browser check with owner and admin logins

## Next

Browser check: on dev, add a protected question to a stage of the draft is NOT allowed (never publish test questions). Instead check with a question loaded by B9c, or test the field through a harness; see Notes.

## Notes

Testing: `supabase test db --linked` cannot reach pgTAP on dev, and local Docker lacks setup tables. Run the
migration's section 2 onward plus `supabase/tests/database/setup_protected_documents.sql` inside one
rolled-back transaction with `docker exec -i supabase_db_ucrm psql -U postgres -At -q`.
Migrations go to dev with `npx supabase db push` (the Supabase MCP needed re-sign-in).
Answer saves never delete documents; only the remove route does. A file left out of an answer (client chose "not yet") stays until Jafar deletes it or its 90 days run; his Setup tab marks it "Not in an answer".

Jafar's decisions (2026-10-04, after comparing with GoHighLevel's port-in and A2P flow):
1. Only the owner and Jafar can open a protected document; an admin can upload it and sees "received"; never in the File library.
2. No transfer PIN in setup; a one-time protected step asks for it when Uplift submits the move (as GHL does).
3. No signed-letter upload; Twilio emails the letter to B8's approver to sign online.
4. Deleted automatically 90 days after the registration or move it served is finished; Jafar can delete sooner.
5. Every upload, open and removal is recorded; owner and Jafar both see the list.
6. A US client may optionally upload the IRS CP-575 tax letter (protected) instead of only typing; never required.
