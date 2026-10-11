# B12 Connected proof — part note

**State:** Paused 2026-10-11. Fresh Contractor journey through Setup, review, Ready, preview, launch approval (Pat Proof, 10:10 AM) and Mark as live (version 1, 10:14 AM, pressed by Jafar) all observed; the "now live" email was sent.

**Method:** The public form only works through `https://app.upliftcontractor.com` (never click or bypass the Cloudflare check). Everything after uses `http://localhost:5173`. Logins are in `Login.md`. `/jafar` and the app keep separate sessions. `dev.jafarkhan@gmail.com` is Chrome Gmail slot `/u/2`.

**Done (observed)**
- Application "B12 Proof Roofing" `73e70294-3ed6-4365-ab38-f7685eea3674` → Contractor · Roofing → payment → organization `9b1c698f-93df-4151-8a0d-00ec406a46c8` → owner login → Client, Request, Quote, Job, Invoice, payment, Paid. Package-limited menu; access comparison same, no clinical capability. Raad LTD as `finance`: history intact, `/pipeline` refused.
- Setup: 5 tasks sent, Uplift review, Ready, preview v1; all 3 cards "Looks right".
- Request Form "Request a roof quote" published (not submitted as a customer). Payments page needs a real Stripe key, untried.
- All 4 launch checks closed as Doesn't apply with honest reasons (email not on for this test business; Files scanner needs Docker, not installed here; Payments needs Stripe; no real accounts; fresh start). Approval link emailed to Pat Proof (`dev.jafarkhan+b12proof@gmail.com`), resent 9:27 AM; the 9:02 link no longer works. Link valid to Nov 10.

**Raad facts:** Raad LTD `18f0d717-904e-48d8-bd99-9df7e3844cda` has a verified sender `office@mail.test.upliftcontractor.com` and a Stripe sandbox (test mode). A "Raad LTD email test" reached Gmail on Sep 26.

**System email (fixed on `main`):** sender name is "Uplift"; no Reply-To until `SYSTEM_REPLY_TO_EMAIL` is set. Jafar has no Uplift mailbox; his plan is an in-app mailbox in `/jafar`, a later release (Jafar business management campaign). Business sender names now reject addresses, links and line breaks. Open for Jafar: the paused and grace screens show `hello@upliftcontractor.com`, which may not exist.

**Still to run:** support message; overdue pause and recovery; a Visit on the Job; an issued quote/invoice link on an existing org; Raad sandbox payment; a closed public form (unit/database-tested only). Note: Claude's click on the approval tick-box and on Mark as live was blocked or did nothing; Jafar pressed both.

**Next:** Prove the tax fix once on the live app while doing the Visit-on-Job check (new job, set tax on the job, Create invoice; the invoice should start with that tax; the dev server reloads whenever another session edits files, so do it when none is writing). Then Raad sandbox payment, then the rest of "Still to run" (the support message and the live-state checks now that B12 is live); update `stages/D-migration-proof.md`. Training and handover pack on B12 are untouched.

**Findings for Jafar:** the public submit took about 20 seconds; the quote's tax did not carry to the invoice ($486 job, $450 invoice) — FIXED 2026-10-11 in `e756da3e` (migration `20261203090000`, test `supabase/tests/database/invoice_inherits_job_tax.sql`, 9 assertions green on the remote database); Setup label reads "How many van do you have?"; the client's Setup page has no "I approve" button when every card is "Looks right"; Schedule's "Today" week showed Oct 4–10 on Oct 11 (check timezone); Chrome screenshots timed out twice. Stale test: `invoices_source_claims_and_chains.sql` assertion 47 uses a 2026-09-30 due date, so it reads "past due" now; unrelated to tax.
