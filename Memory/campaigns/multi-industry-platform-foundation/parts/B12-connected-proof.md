# B12 Connected proof — part note

**State:** Paused 2026-10-11. Core Contractor journey and the whole Setup → Uplift review → Ready → preview path observed; launch is next.

**Method:** The public form only works through `https://app.upliftcontractor.com` (Cloudflare check passes by itself; never click or bypass it). Everything after that uses `http://localhost:5173`. Logins are in `Login.md` (new: B12 Proof Roofing owner). `/jafar` and the app keep separate sessions.

**Done (observed)**
- Application "B12 Proof Roofing" `73e70294-3ed6-4365-ab38-f7685eea3674` → kind of business confirmed (Contractor · Roofing) → reviewed → test payment recorded → account activated → organization `9b1c698f-93df-4151-8a0d-00ec406a46c8` → setup link → password → owner login.
- Package-limited menu. Client → Request → Quote #1 ($486 with tax; emailing refused while billing closed, then for no business email, so "I already sent it") → client link → approved → Job #1 → Invoice #1 → payment → Paid, $0 balance.
- Access comparison: Same access (9 capabilities, owner 65→65), no clinical capability.
- Existing Raad LTD as `finance`: history intact, `/pipeline` refused.

**Still to run:** launch checks and Mark as live; support message; overdue pause and recovery; a Visit on the Job; an issued quote/invoice link on an existing org; a closed public form (none exists; unit/database-tested only).

**Findings for Jafar:** the submit took about 20 seconds; the quote's tax did not carry to the invoice (job showed $486, invoice started at $450, tax re-entered by hand).

**Setup → preview (2026-10-11, observed):** all 5 Setup tasks finished and sent to Uplift. In `/jafar` the owner login accepted all five, recorded Ready, wrote and released preview version 1 (3 cards, client emailed). As the B12 owner, all 3 cards marked "Looks right"; nothing to send back. Launch check "Imported records add up" marked Doesn't apply (client started fresh).

**Launch checks (2026-10-11):** Jafar chose "split it". Three lines still unticked, on purpose. Package tried: Schedule, Files (upload works, but the file stays "Still being checked", so the scanner worker probably isn't running locally), Settings, Request Forms (none built yet). Dashboard says Email and texts are "not switched on" until Uplift verifies the sender address, so no real test email can go out yet.

**Launch checks, later (2026-10-11):** Request Form "Request a roof quote" built and published (form `23cb2288-78c4-4c51-97a2-2a25c250369a`; not submitted as a customer). Payments page opens but needs a real Stripe key, so untried. "Owns its accounts" marked Doesn't apply (test business). Two lines left: "Emails from the system arrive" and "Everything else in the package works".

**Launch approval asked (2026-10-11 9:02 AM):** Jafar said "you choose". Email line and "Everything else" both marked Doesn't apply with honest reasons (email not on for this test business; Files scanner needs Docker, not installed on this computer; Payments needs a Stripe key). All 4 lines closed; approval link emailed to Pat Proof (`dev.jafarkhan+b12proof@gmail.com`, lands in the `dev.jafarkhan@gmail.com` inbox, not the `profile.mdjafarkhan` one). Link works until Nov 10.

**Raad facts (read-only check):** Raad LTD (`18f0d717-904e-48d8-bd99-9df7e3844cda`) has a verified, enabled sender `office@mail.test.upliftcontractor.com` and a Stripe sandbox connection (test mode, key ending I8DO). Owed on Raad: one real test email to Jafar's inbox and one sandbox payment on an invoice (promised in the line reasons above).

**Next:** (1) Jafar opens the approval email in the dev.jafarkhan inbox and approves as the B12 owner (or uses "Record an approval given another way"). (2) Mark live in `/jafar` Setup tab. (3) Raad email and sandbox payment proof. (4) Rest of "Still to run"; update `stages/D-migration-proof.md`.

**Also seen:** Schedule's "Today" week showed Oct 4–10 on Oct 11 (check timezone); browser screenshots timed out twice in a row, so the Chrome session may need a restart.

**More findings:** Setup label reads "How many van do you have?"; the client's Setup page offers no "I approve" button when every card is "Looks right".
