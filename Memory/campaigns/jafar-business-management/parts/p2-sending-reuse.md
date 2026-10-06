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
- [ ] Ask Jafar whether he accepts Hostinger behind the in-app inbox, or wants the larger UCRM-managed mailbox project.
- [ ] Verify the chosen route's integration and sending policy; refine the plan and close P2.

## Next

Show Jafar `docs/research/jafar-full-mailbox-options-2026-10-06.md` in plain language. Ask exactly: “Is it okay to keep one Hostinger mailbox working quietly behind `/jafar` while you and your team do all daily email work inside the app, or is canceling Hostinger important enough to make building our own full mailbox a separate large project?” Pause for his answer. Do not buy a plan, change MX, or send mail.
