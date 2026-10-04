# C3b — Review a section, client's side (then C3c)

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 4, § 5; ADR 0005 (accepted layer)
**Code:** `main`
**Done when:** Returned section links the client straight to it; other sections stay accepted

## Decisions (Jafar, 2026-10-04, all recommended; model: Content Snare approve / send back with reason)

1. Return = a note plus ticked questions; the client sees those questions highlighted.
2. Ask a question = a support chat with the section attached — built in C3a.
3. Client sees "Accepted by Uplift"; changing an accepted section puts it back for review on the next send.
4. Help requests: "Uplift's to-do"; a section can be accepted with them open; an item closes when Jafar records Uplift's answer (C3c).
5. A return emails owners and admins straight to that section, banner on /setup, reminders restart.

## What C3a left for this part

- Review state per section: `readSectionReviews` in `src/lib/server/setup/client-page.ts`, rules in `src/lib/setup/review.ts`. The table is readable by the org's admins (RLS).
- `SetupAnswerList` takes `flagged` (highlights "Sent back" questions) — reuse on the client's section page.
- A return already restarts the reminder clock in the database, but `setupSummary` (`src/lib/server/setup/read.ts`) still says "nothing next" once sent, so a reminder records "finished". C3b must make a returned section the next task, and word the reminder for it.
- Raad LTD's "Your business" is Accepted on send 1 (dev). Send it back again to test the client side.

## Steps

- [x] Client task list + section page: badges, banner on /setup, note and highlighted questions (also dashboard card)
- [x] Email to owners and admins on a return (`src/lib/server/setup/return-email.ts`, key per decision time), linking to `/setup/<section>`
- [x] `setupSummary` next = first returned section; reminder wording; onboarding list "fix_returned" (migration 20261027090000, pushed)
- [x] Unit tests
- [ ] Browser check as the Raad owner

## Next

Browser check: as Jafar, send back Raad LTD's "Your business" (Setup tab of `/jafar/organizations/[id]`) ticking a question; then as the Raad owner check `/setup` banner and badge, the section's note and highlight, the dashboard card, and `/jafar/onboarding` shows "Waiting for their information". Then C3c.
