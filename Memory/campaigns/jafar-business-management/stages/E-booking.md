# Jafar Business Management — stage E: Public booking

The `/jafar` calendar is the only source of availability. Bookings are switched off until Jafar shares the link. `src/routes/book/booking.e2e.ts` needs Cloudflare's Turnstile test keys in the shell (see its header). No Zoom or Meet connection exists yet; see `docs/research/jafar-video-booking-links-2026-10-07.md`.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| E1 Booking page with instant booking | Booking settings (availability, a phone meeting type, Jafar host, link on/off); public page; instant confirmation email; calendar and history entry | C2 | Two visitors try the same 3pm slot and only one gets it; the winner's booking shows on the calendar and in history | Done 2026-10-09 |
| E2 Reschedule, cancel, and approval mode | Secure links with Jafar's deadline; approval mode with request receipt and recheck on approval | E1 | A visitor moves a booking: old time freed, reminders replaced; an approval-mode request never reserves the slot | Not started |
| E2b Visitor reminders | Visitor reminder emails Jafar configures before the call, and an .ics calendar file with confirmations (plan: "optional reminders Jafar configures") | E2 | A visitor booked for tomorrow gets the reminder at Jafar's chosen time, with a working calendar file | Not started |
| E3 Meeting types and hosts | Several meeting types, eligible hosts, one default host, host change with visitor notice | E2, D2 | Changing a booking's host checks the new host's time and emails the visitor | Not started |
| E4 Custom video links and Zoom | Custom-link mode with "details to follow" notice and host reminder; Zoom connection creating one meeting per booking, updated or cancelled with it | E2 | A Zoom booking emails its own join link; cancelling it cancels the Zoom meeting | Not started |
| E5 Google Meet | Google connection creating one Meet per booking, updated or cancelled with it | E4 | A Meet booking emails its own join link; moving it updates the Meet event | Not started |
