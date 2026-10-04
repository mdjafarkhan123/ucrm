# B9c — Texting registration stage (built 2026-10-04; waits for Jafar’s publish)

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` §3.6, §9; blueprint stage 9 and "Porting or hosted-number access"
**Code:** `main`
**Done when:** Stage in draft, Calls and texting only; once Jafar publishes, the protected bill question passes the login check below

## Steps

- [x] Load blueprint stage 9 into the draft with `private.setup_load_starter_stage` (as B3b's migration does); the moving-number bill is a `protected_file` question; no PIN or signed-letter question
- [ ] After Jafar's publish: setup page with the admin login shows "Received", no open link or History; owner login opens it and sees History; Jafar's organization page Setup tab lists it with Open, History, "Provider step finished", "Delete now"

## Next

Stage 9 ("texting") and stage 8 with the bill (`calls.port_bill`) are in the dev draft (migration `20261020090000`).
When Jafar has published, run the login check in Steps. Until then B10 can go ahead.
Open question for Jafar (not blocking): stage 9 adds "When may automatic texts go out?" (8am–9pm recommended), which plan §3.6 asks for but the blueprint table leaves out.

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
