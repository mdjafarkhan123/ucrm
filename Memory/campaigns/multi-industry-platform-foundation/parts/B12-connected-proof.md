# B12 Connected proof — part note

**State:** Paused 2026-10-10. Core Contractor journey observed; the rest is below.

**Method:** The public form only works through `https://app.upliftcontractor.com` (Cloudflare check passes by itself; never click or bypass it). Everything after that uses `http://localhost:5173`. Logins are in `Login.md` (new: B12 Proof Roofing owner). `/jafar` and the app keep separate sessions.

**Done (observed)**
- Application "B12 Proof Roofing" `73e70294-3ed6-4365-ab38-f7685eea3674` → kind of business confirmed (Contractor · Roofing) → reviewed → test payment recorded → account activated → organization `9b1c698f-93df-4151-8a0d-00ec406a46c8` → setup link (read from the stored email copy) → password → owner login.
- Package-limited menu. Client `cb46492e…` → Request `a846a5a8…` → Quote #1 `98d8cd2d…` ($450 + 8% = $486). Emailing refused while billing closed; Jafar opened only `customer_billing`; email then refused for no business email (Settings → Email) → "I already sent it" → client link → Casey approved → Job #1 `71a0e343…` → Invoice #1 `436bd981…` → payment → Paid, $0 balance.
- Access comparison: Same access (9 capabilities, owner 65→65), no clinical capability. Other three areas still Not Reviewed. Dashboard explains closed areas.
- Existing Raad LTD as `finance`: history intact, `/pipeline` refused.

**Still to run:** Setup tasks, Uplift review, preview/approval, Mark as live; support message; overdue pause and recovery; a Visit on the Job; an issued quote/invoice link on an existing org; a closed public form (none exists; unit/database-tested only).

**Findings for Jafar:** the submit took about 20 seconds; the quote's tax did not carry to the invoice (job showed $486, invoice started at $450, tax re-entered by hand); the invoice's recipient box said no phone or email yet.

**Setup progress (2026-10-11, B12 owner login, `/setup`):** "Your business" and "Services and service area" finished (2 of 5). "Brand, photos and proof" is on step 2 of 3 (step 1 done; everything in it is optional). Not started: "How your CRM should work", "Move your existing data", then "Check and send to Uplift". Answers save as you go. Tip: the form's dropdowns accept typing then Enter; "Finish this task" names any missing answer.

**Next:** sign in as the B12 owner, finish the three remaining setup tasks, send to Uplift, then review and Mark as live in `/jafar/onboarding`. Then run the rest of "Still to run" and update `stages/D-migration-proof.md`.
