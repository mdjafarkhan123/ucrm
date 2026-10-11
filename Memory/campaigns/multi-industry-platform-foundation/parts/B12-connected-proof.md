# B12 Connected proof — part note

**State:** Paused 2026-10-11. Fresh Contractor journey through Setup, review, Ready, preview, launch approval (Pat Proof, 10:10 AM) and Mark as live (version 1, 10:14 AM, pressed by Jafar) all observed; the "now live" email was sent.

**Method:** The public form only works through `https://app.upliftcontractor.com` (never bypass the Cloudflare check). Everything else uses `http://localhost:5173`; logins in `Login.md`. `/jafar` and the app keep separate sessions. `dev.jafarkhan@gmail.com` is Chrome Gmail slot `/u/2`.

**Done**
- Application "B12 Proof Roofing" `73e70294-3ed6-4365-ab38-f7685eea3674` → Contractor · Roofing → payment → organization `9b1c698f-93df-4151-8a0d-00ec406a46c8` → owner login → Client, Request, Quote, Job, Invoice, payment, Paid. Package-limited menu; access comparison same, no clinical capability. Raad LTD as `finance`: history intact, `/pipeline` refused.
- Setup: 5 tasks sent, review, Ready, preview v1; all cards "Looks right".
- All 4 launch checks closed as Doesn't apply with honest reasons (email not on for this test business; Files scanner needs Docker, not installed here; Payments needs Stripe; no real accounts; fresh start). Launch approved by Pat Proof (`dev.jafarkhan+b12proof@gmail.com`).

**System email (fixed on `main`):** sender name is "Uplift"; no Reply-To until `SYSTEM_REPLY_TO_EMAIL` is set. Jafar has no Uplift mailbox; his plan is an in-app mailbox in `/jafar`, a later release (Jafar business management campaign). Open for Jafar: the paused and grace screens show `hello@upliftcontractor.com`, which may not exist.

**Support proven live (2026-10-11):** from Raad LTD "Chat with Uplift" → saved as an open thread → shown in `/jafar/support` → Uplift reply shown in the same thread (thread `766d676b…`).

**Visit proven live (2026-10-11):** Job #1 → Add one visit (Oct 13) → shows on Schedule; Jobs now reads Upcoming/Today.

**Still to run:** overdue pause and recovery; a closed public form (unit/database-tested only).

**Raad sandbox payment + customer link proven live (2026-10-11):** Raad LTD (`18f0d717-904e-48d8-bd99-9df7e3844cda`, Stripe sandbox) invoice #34 → customer link → Pay now → Stripe test checkout → `payment=success`; invoice Paid, "Card (online)" in history.

**Tax fix proven live (2026-10-11):** Job #2 with 8% custom tax → invoice began with that tax ($432). Test job and unsent draft remain in B12 Proof Roofing.

**Next:** overdue pause and recovery (needs a time skip on B12 Proof Roofing's paid-through date, as package-builder P16 M8 did; wait for Jafar's go-ahead), then the closed public form; update `stages/D-migration-proof.md`. Claim write first; the register refuses while uncommitted design files sit in the main folder.

**Question for Jafar:** should those three Jobs cards show real numbers, and does "Revenue this month" mean invoiced or paid?

**Findings for Jafar:** public submit took about 20 seconds; tax not carrying to the invoice and Jobs ignoring visits are both FIXED (`e756da3e`, `d8091900`) and seen live; the Jobs cards "Visits today", "Completed this month" and "Revenue this month" are still dashes (question above); the Setup label "How many van do you have?" is test text, not in the code; "Approve launch" appears only after Uplift sends the approval request (by design).
