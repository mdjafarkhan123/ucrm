# E6 — Training + handover

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 5 (states 10–11), § 6 last paragraph, § 8
**Code:** `main`
**Done when:** Delivery cannot close until training is scheduled; Jafar's Onboarding list hides delivered clients by default.

## Steps

- [x] Checked: nothing for training or handover exists yet; the wizard asks no training questions
- [ ] Jafar answers round 1 (below); ask any follow-up round
- [ ] Write Jafar's E6 choices into plan § 6
- [ ] Build: Live and Delivered in `$lib/setup/project-state.ts`, training request, Jafar's controls, handover page, list filter
- [ ] Browser-check on Raad LTD, remove test data

## Next

Wait for Jafar's round 1 answers, then do the next unticked step.

## Notes

Research: GuideCX and Rocketlane (the client fills in tasks, and the vendor marks the project complete); web agency
handover practice (a single handover document with access, ownership and a recorded walkthrough).
Round 1 questions asked 2026-10-06 (my recommendation is in brackets):

1. How does a project become Live? (Jafar presses "Mark as live" after launching; the client's owners and admins get a "you're live" email.)
2. When can the client fill in training details? (From Ready for Uplift onward, on the Setup page, owners and admins only.)
3. How is the time booked? (The client gives preferred times; Jafar sets the time and pastes a Meet/Zoom link; the client is emailed. No booking calendar yet.)
4. The recording? (Jafar pastes a private video link after training, only if the client agreed to recording. No video uploads.)
5. Can a client skip training? (Yes, the owner can say "We don't need training"; that counts as settled.)
6. Delivered needs training held, or only booked? (Booked or skipped is enough, as the plan says; Jafar presses "Mark as delivered".)
7. Handover pack form? (A page in the app, printable as PDF; auto-filled with approvals, open outside waits, and the support route; Jafar writes the access/ownership summary and adds guide links.)
8. After Delivered? (The dashboard card shows "Project delivered" for 14 days, then hides; the handover page stays reachable from Settings.)
