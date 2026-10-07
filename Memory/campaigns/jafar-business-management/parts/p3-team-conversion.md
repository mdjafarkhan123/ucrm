# P3 — Team, booking, Settings, and conversion details

**Campaign:** jafar-business-management · **Plan:** `docs/jafar-business-management-behavior-contract.md` §§ Turn interest into a deal, Know what to do today, Team access
**Code:** `main`
**Done when:** Remaining behavior questions are settled and Jafar approves the product plan.

## Steps

- [x] Check existing contractor Schedule, quote, package, payment/onboarding, and `/jafar` permission boundaries against mature sales workflows.
- [x] Record Jafar's choices: the approved lead list stays idle until he sends one message or starts a sequence; four starting team roles are built even while he works alone; unassigned work defaults to him.
- [x] Record the sales handoff: Sales can mark Won only after separately confirmed payment; onboarding starts with Jafar's assigned person, otherwise Jafar.
- [x] Record Jafar's sales calendar requirement and his pricing-page link as the first offer path; preserve the price/terms shared in the Deal.
- [x] Agree flexible reminder count and timing, a public prospect booking link with a `/jafar` Booking settings tab, and starting role areas.
- [x] Check contractor booking and current `/jafar` Settings against official HubSpot, Calendly, Pipedrive, and Jobber patterns; save `docs/research/jafar-booking-settings-patterns-2026-10-07.md`.
- [x] Settle `/jafar` as the only calendar, secure self-reschedule/cancel, configurable meeting types with named eligible hosts, and the six-group Settings home.
- [ ] Settle instant confirmation versus approval, which calendar items block a host, visitor notices, and online meeting-link behavior.
- [ ] Walk Jafar through the updated product plan and record his approval or corrections.

## Next

Wait for Jafar's answers below. Then update the plan and ask for approval of the whole product plan before P4 release-scope selection. No coding, purchase, DNS change, or live sending is authorized by this planning part.

## Waiting for Jafar

Q1 When a visitor picks a free time, should UCRM confirm it immediately? A (recommended): yes, and Booking settings let you switch to “request my approval” when needed. B: every booking waits for your approval.

Q2 If you add a task due at 3 pm, does that make you busy for a 3 pm call? A (recommended): meetings, calendar events, and explicit Busy blocks hide a time; a task does not unless you mark its time Busy. B: every timed task blocks booking.

Q3 After a visitor books, should UCRM email them a confirmation and optional reminders you set, and email changes when they reschedule or cancel? A (recommended): yes. B: only show confirmation on screen.

Q4 For an online call, how should the visitor get the video link? A (recommended): you add a unique meeting link to that booking, and UCRM sends it in an updated confirmation. B: UCRM creates a fresh Google Meet or Zoom link for each booking.
