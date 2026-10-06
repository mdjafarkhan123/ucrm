# P2 — Sending and reuse limits

**Campaign:** jafar-business-management · **Plan:** `docs/jafar-business-management-behavior-contract.md` § Reach out and handle the conversation
**Code:** `main`
**Done when:** The plan promises only sending and reuse that can actually work.

## Steps

- [x] Check current Brevo platform email, contractor SES/Marketing, Automation spacing, owner Support inbox, and single-owner access in the repository.
- [x] Review official provider and representative country rules; save findings in `docs/research/jafar-outreach-sending-reuse-2026-10-06.md`.
- [x] Record the safe product boundary: all non-Asia trade leads are recordable; automatic sends need a verified sender and per-recipient channel checks.
- [x] Ask Jafar where Uplift sales replies currently arrive and which mailbox hosts that address. He plans `info@upliftcontractor.com`, with a Hostinger mailbox not yet confirmed active, and prefers an in-app inbox.
- [x] Compare Hostinger's current Mail API with a full UCRM mailbox over SES; save the comparison in `docs/research/jafar-full-mailbox-options-2026-10-06.md`.
- [x] Record Jafar's choice: no Hostinger email plan; create multiple Uplift addresses in `/jafar`, with per-address inboxes and a permission-aware Unified Inbox.
- [x] Check contractor Unified Inbox reuse: share suitable UI, conversation and SES pieces; keep contractor organization data and permissions separate from Uplift mailboxes.
- [ ] Verify the chosen route's domain and SES readiness, general inbound and recovery needs, and a provider-approved outbound path; refine the plan and close P2.

## Next

Use `docs/research/jafar-full-mailbox-options-2026-10-06.md` and the mailbox section of the behavior plan. Verify the domain's existing DNS/mail state, SES receiving and sender readiness, mailbox recovery requirements, and a permitted provider path for approved prospect email. Record verified limits in the plan before closing P2. Do not buy a plan, change MX, build, or send mail during planning.
