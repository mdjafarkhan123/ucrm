# B12 Connected proof — part note

**State:** Paused 2026-10-11. Core Contractor journey and the whole Setup → Uplift review → Ready → preview path observed; launch is next.

**Method:** The public form only works through `https://app.upliftcontractor.com` (Cloudflare check passes by itself; never click or bypass it). Everything after that uses `http://localhost:5173`. Logins are in `Login.md` (new: B12 Proof Roofing owner). `/jafar` and the app keep separate sessions.

**Done (observed)**
- Application "B12 Proof Roofing" `73e70294-3ed6-4365-ab38-f7685eea3674` → kind of business confirmed (Contractor · Roofing) → reviewed → test payment recorded → account activated → organization `9b1c698f-93df-4151-8a0d-00ec406a46c8` → setup link (read from the stored email copy) → password → owner login.
- Package-limited menu. Client `cb46492e…` → Request `a846a5a8…` → Quote #1 `98d8cd2d…` ($450 + 8% = $486). Emailing refused while billing closed; Jafar opened only `customer_billing`; email then refused for no business email (Settings → Email) → "I already sent it" → client link → Casey approved → Job #1 `71a0e343…` → Invoice #1 `436bd981…` → payment → Paid, $0 balance.
- Access comparison: Same access (9 capabilities, owner 65→65), no clinical capability. Other three areas still Not Reviewed. Dashboard explains closed areas.
- Existing Raad LTD as `finance`: history intact, `/pipeline` refused.

**Still to run:** launch checks and Mark as live; support message; overdue pause and recovery; a Visit on the Job; an issued quote/invoice link on an existing org; a closed public form (none exists; unit/database-tested only).

**Findings for Jafar:** the submit took about 20 seconds; the quote's tax did not carry to the invoice (job showed $486, invoice started at $450, tax re-entered by hand); the invoice's recipient box said no phone or email yet.

**Setup → preview (2026-10-11, observed):** all 5 Setup tasks finished and sent to Uplift (Sent 6:33 AM). In `/jafar` the owner login accepted all five, recorded Ready (build starts Mon Oct 12; client review Oct 20–23), wrote and released preview version 1 (3 cards, client emailed). As the B12 owner, all 3 cards marked "Looks right"; nothing to send back. Launch check "Imported records add up" marked Doesn't apply (client started fresh).

**Next:** in `/jafar/organizations/9b1c698f-93df-4151-8a0d-00ec406a46c8?tab=setup`, three launch lines are left: "Emails from the system arrive" (needs a real test email seen in the inbox, not spam), "The business owns its accounts and logins", "Everything else in the package works". Do only what is true; then Ask for launch approval, approve as the B12 owner, Mark the system live. Then the rest of "Still to run"; update `stages/D-migration-proof.md`.

**More findings:** the Setup label reads "How many van do you have?"; a Chrome screenshot sometimes times out a few seconds after a click (wait, retry); the client's Setup page offers no "I approve" button when every card is "Looks right".
