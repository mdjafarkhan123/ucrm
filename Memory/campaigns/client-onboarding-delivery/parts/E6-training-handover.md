# E6 — Training + handover

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` §5–6, §8
**Code:** `main`
**Done when:** A client can arrange or skip training, see the handover page, and receive a durable Live/Delivered record; delivery cannot close without the agreed checks; Jafar's Onboarding list hides delivered clients by default.

## Steps

- [x] Checked: no training or handover records exist yet; the wizard asks no training questions
- [x] Jafar approved all E6 choices on 2026-10-06; plan §6 records them
- [ ] Build the client training request and consent, Jafar's booking/live/delivery controls, handover page, notices, project states, and list filter
- [ ] Browser-check on Raad LTD, remove test data

## Next

Jafar asked to stop before coding and switch to Claude. In a new session, first tell him coding will begin, then claim E6 and build from plan §6. No E6 application code was changed during planning. Check the plan's Live, booking/skip, recording-withdrawal, delivery gate, handover access, and email rules before coding.

## Notes

The previously approved contract said training must be scheduled; Jafar explicitly added an owner skip. A cancelled booking before delivery blocks closing until rebooked or skipped. After delivery, changing a booking keeps the delivered state and updates history. A consent withdrawal hides the link in the app and leaves Jafar a task to restrict the external video. The handover page is for owners/admins; open provider actions do not block delivery.
