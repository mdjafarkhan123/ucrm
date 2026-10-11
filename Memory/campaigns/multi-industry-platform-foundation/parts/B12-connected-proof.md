# B12 Connected proof — part note

**State:** Paused 2026-10-11. Fresh Contractor journey, Setup → review → Ready → preview, and all launch checks are done; launch approval is waiting.

**Method:** The public form only works through `https://app.upliftcontractor.com` (never click or bypass the Cloudflare check). Everything after uses `http://localhost:5173`. Logins are in `Login.md`. `/jafar` and the app keep separate sessions. `dev.jafarkhan@gmail.com` is Chrome Gmail slot `/u/2`.

**Done (observed)**
- Application "B12 Proof Roofing" `73e70294-3ed6-4365-ab38-f7685eea3674` → Contractor · Roofing → payment → organization `9b1c698f-93df-4151-8a0d-00ec406a46c8` → owner login → Client, Request, Quote, Job, Invoice, payment, Paid. Package-limited menu; access comparison same, no clinical capability. Raad LTD as `finance`: history intact, `/pipeline` refused.
- Setup: 5 tasks sent, Uplift review, Ready, preview v1; all 3 cards "Looks right".
- Request Form "Request a roof quote" published (not submitted as a customer). Payments page needs a real Stripe key, untried.
- All 4 launch checks closed as Doesn't apply with honest reasons (email not on for this test business; Files scanner needs Docker, not installed here; Payments needs Stripe; no real accounts; fresh start). Approval link emailed to Pat Proof (`dev.jafarkhan+b12proof@gmail.com`), resent 9:27 AM; the 9:02 link no longer works. Link valid to Nov 10.

**Raad facts:** Raad LTD `18f0d717-904e-48d8-bd99-9df7e3844cda` has a verified sender `office@mail.test.upliftcontractor.com` and a Stripe sandbox (test mode). A "Raad LTD email test" reached Gmail on Sep 26.

**System email (fixed on `main`):** sender name is "Uplift"; no Reply-To until `SYSTEM_REPLY_TO_EMAIL` is set. Jafar has no Uplift mailbox; his plan is an in-app mailbox in `/jafar`, a later release (Jafar business management campaign). Business sender names now reject addresses, links and line breaks. Open for Jafar: the paused and grace screens show `hello@upliftcontractor.com`, which may not exist.

**Still to run:** support message; overdue pause and recovery; a Visit on the Job; an issued quote/invoice link on an existing org; Raad sandbox payment; a closed public form (unit/database-tested only).

**Next:** (1) Jafar clicks "Review and approve" in the 9:27 email, or says "approve as B12 owner" (the click was blocked for me). (2) Mark live in `/jafar` Setup tab. (3) Raad sandbox payment, then "Still to run"; update `stages/D-migration-proof.md`.

**Findings for Jafar:** the public submit took about 20 seconds; the quote's tax did not carry to the invoice ($486 job, $450 invoice); Setup label reads "How many van do you have?"; the client's Setup page has no "I approve" button when every card is "Looks right"; Schedule's "Today" week showed Oct 4–10 on Oct 11 (check timezone); Chrome screenshots timed out twice.
