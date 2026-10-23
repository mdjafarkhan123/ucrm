# Stage 10 Part 5 — Sending rules per country

**Campaign:** communications-activation · **Plan:** `docs/global-sms-behavior-contract.md` § Part 5
**Stage:** 5a built and applied 2026-10-23 (branch `claude/stage10-part5`). 5b–5d not started.
**Done when:** a business texts only countries Uplift switched on, from a number that can text them; Uplift
works the requests in Texting setup (`v6Jtu`); opt-out words are set per language; merged to main.

## Slices

- **5a — built 2026-10-23.** Migration `20261229120000_sms_destinations.sql` **applied**: customer country from
  the number (`private.sms_phone_country`, rows from `scripts/generate-phone-country-prefixes.mjs`); per-business
  countries `communication_sms_destinations` (+ `_events`); commands request / switch on / turn off; one route
  check (`private.communication_sms_route_check`) used by enqueue, dispatch (claim) and the reply estimate
  (`communication_sms_reply_route_preview`). Price is the customer's country; real MMS only US/CA ↔ US/CA;
  sender Geo-match when none chosen; +1 numbers text US+CA, others their own country; US registration only
  for US customers from +1 local numbers (non-US senders no longer need a registration). A finished number
  order asks for home + number country. Route `api/communications/conversations/[clientId]/sms-estimate`.
- **5b — next.** Control Room Texting setup page (queue, Twilio permission task, "I did it", Can't turn on) and
  the business's countries card (`v6Jtu`). API must check Jafar permission; use switch_on / turn_off commands.
- **5c — needs a Pencil drawing first.** Contractor's "Text customers in another country" link (`NbWfA`) has no
  pop-up drawn; ask Jafar. Also show the WHERE YOU CAN TEXT box from destinations.
- **5d.** Opt-out words per language (Opt-out task in `v6Jtu`), recipient-local quiet hours.

## Proof so far

- Rolled-back live-DB runs: 6,798/6,800 random valid numbers match libphonenumber (misses: a short CA special
  range, one tiny JE block); route states (setting up, off with business message, wrong-country number, US
  registration needed, ready + MMS); enqueue → claim sent; turned-off country cancels and releases the hold.
- `npx vitest run` communications folders: 582 pass; 1 fails on main too (`number-readiness.spec.ts` toll-free
  card) — reported to Jafar, not fixed.
- Twilio's GeoPermissions API answers 404 for our account, so switching on stays a dashboard step.
