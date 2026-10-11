# B12 Connected proof — part note

**State:** Paused 2026-10-11. Fresh Contractor journey through Setup, review, Ready, preview, launch approval (Pat Proof, 10:10 AM) and Mark as live (version 1, 10:14 AM, pressed by Jafar) all observed; the "now live" email was sent.

**Method:** The public form only works through `https://app.upliftcontractor.com` (never bypass the Cloudflare check). Everything else uses `http://localhost:5173`; logins in `Login.md`. `/jafar` and the app keep separate sessions. `dev.jafarkhan@gmail.com` is Chrome Gmail slot `/u/2`.

**Done**
- Application "B12 Proof Roofing" `73e70294-3ed6-4365-ab38-f7685eea3674` → Contractor · Roofing → payment → organization `9b1c698f-93df-4151-8a0d-00ec406a46c8` → owner login → Client, Request, Quote, Job, Invoice, payment, Paid. Package-limited menu; access comparison same, no clinical capability. Raad LTD as `finance`: history intact, `/pipeline` refused.
- Setup: 5 tasks sent, review, Ready, preview v1; all cards "Looks right".
- All 4 launch checks closed as Doesn't apply with honest reasons (email not on for this test business; Files scanner needs Docker, not installed here; Payments needs Stripe; no real accounts; fresh start). Launch approved by Pat Proof (`dev.jafarkhan+b12proof@gmail.com`).

**System email (fixed on `main`):** sender name is "Uplift"; no Reply-To until `SYSTEM_REPLY_TO_EMAIL` is set. Jafar has no Uplift mailbox; his plan is an in-app mailbox in `/jafar`, a later release (Jafar business management campaign). Open for Jafar: the paused and grace screens show `hello@upliftcontractor.com`, which may not exist.

**Support proven live (2026-10-11):** from Raad LTD "Chat with Uplift" → saved as an open thread → shown in `/jafar/support` → Uplift reply shown in the same thread (thread `766d676b…`).

**Visit proven live (2026-10-11):** Job #1 visit (Oct 13) shows on Schedule.

**Still to run:** a closed public form (unit/database-tested only).

**Sandbox payment proven live (2026-10-11):** Raad LTD invoice #34 → customer link → Stripe test checkout → Paid, "Card (online)".

**Tax fix proven live (2026-10-11):** Job #2 with 8% custom tax → invoice began with that tax ($432). Test job and unsent draft remain in B12 Proof Roofing.

**Overdue proven live (2026-10-11):** B12 Proof Roofing 3 days overdue → grace banner; 9 days → paused screen, Control Room Suspended; test payment recorded and dates confirmed in `/jafar` Billing → active, paid-through now 2026-12-09, records intact.

**Next:** the closed public form (needs `https://app.upliftcontractor.com` for the public path), then update `stages/D-migration-proof.md` and close B12. The claim register refuses while another campaign's design files are uncommitted; none are mine.

**Jobs cards fixed (`910e5791`):** Visits today, Completed visits (past 30 days), Collected this month now show real numbers. "Revenue" was read as money paid; Jafar can switch it to invoiced.

**Findings for Jafar:** public submit took about 20 seconds; tax not carrying to the invoice and Jobs ignoring visits are both FIXED (`e756da3e`, `d8091900`) and seen live; the Jobs cards are now real (above); the Setup label "How many van do you have?" is test text, not in the code; "Approve launch" appears only after Uplift sends the approval request (by design).
