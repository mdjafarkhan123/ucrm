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

**Next:** (1) Ask Jafar to check Gmail for a test email to `dev.jafarkhan+b12proof@gmail.com` once the sender address is verified, or decide to skip it. (2) Build and publish one Request Form, try Payments, then tick "Everything else in the package works". (3) Mark "owns its accounts" Doesn't apply (fake business). (4) Ask for launch approval, approve as the B12 owner, Mark live. (5) The rest of "Still to run"; update `stages/D-migration-proof.md`.

**Also seen:** Schedule's "Today" week showed Oct 4–10 on Oct 11 (check timezone); browser screenshots timed out twice in a row, so the Chrome session may need a restart.

**More findings:** Setup label reads "How many van do you have?"; the client's Setup page offers no "I approve" button when every card is "Looks right".
