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
- [x] Settle instant confirmation versus approval, which calendar items block a host, visitor notices, and phone/video choices.
- [x] Verify Zoom and Google Meet can provide a separate link for each booking; see `docs/research/jafar-video-booking-links-2026-10-07.md`.
- [ ] Settle how Zoom or Google Meet links are made and delivered.
- [ ] Walk Jafar through the updated product plan and record his approval or corrections.

## Next

Jafar accepted immediate booking confirmation by default with a setting to require approval; meetings, calendar events, and Busy blocks hide slots, while ordinary tasks do not; confirmation, reminders, and changes email the visitor. He wants each meeting type to choose phone or video, with Zoom and Google Meet as video options. The plan records these choices. Ask the question below and wait. Then update the plan, walk him through it, and seek approval before P4. No coding or live changes.

## Waiting for Jafar

❓ **Q1 — Video link for a booked call:** Imagine a visitor books Tuesday at 3 pm for a Google Meet call. Should UCRM create a fresh Meet link automatically and email it with the booking confirmation? If you choose Zoom for that meeting type, it would do the same with Zoom. You would connect your chosen provider account once in Booking settings, and UCRM would update or cancel that provider meeting when the booking changes. Or would you rather paste a link into each booking yourself, so UCRM emails it afterward?

➡️ I recommend automatic links. They fit immediate booking and remove a step you could forget. Your `/jafar` calendar would still decide when you are free; connecting Meet or Zoom for a video link would not make its outside calendar the source of availability.
