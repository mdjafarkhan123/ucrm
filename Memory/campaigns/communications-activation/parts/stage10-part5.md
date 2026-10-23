# Stage 10 Part 5 — Sending rules per country

**Campaign:** communications-activation · **Plan:** `docs/global-sms-behavior-contract.md` § Part 5
**Stage:** 5a built 2026-10-23. 5b built 2026-10-23, **Waiting to merge** (main was owned by the Pencil tidy session; branch
`claude/stage10-part5b`). 5b-2, 5c, 5d not started.
**Done when:** a business texts only countries Uplift switched on, from a number that can text them; Uplift
works the requests in Texting setup (`v6Jtu`); opt-out words are set per language; merged to main.

## Slices

- **5a — built 2026-10-23.** Migration `20261229120000_sms_destinations.sql` **applied**: customer country from
  the number (`private.sms_phone_country`, rows from `scripts/generate-phone-country-prefixes.mjs`); per-business
  countries `communication_sms_destinations` (+ `_events`); commands request / switch on / turn off; one route
  check (`private.communication_sms_route_check`) used by enqueue, dispatch (claim) and the reply estimate
  (`communication_sms_reply_route_preview`). +1 numbers text US+CA, others their own country; US registration
  only for US customers from +1 local numbers. Route `api/communications/conversations/[clientId]/sms-estimate`.
- **5b — built 2026-10-23.** Migrations `20261230120000_sms_destination_ops.sql` and `20261230130000_…_queue_finished`
  **applied**: history rows keep the Control Room person's name (`actor_name`; no Supabase user there); switch on /
  turn off take it; `communication_sms_destination_queue()` (tasks, page numbers, last day's finished) and
  `communication_sms_organization_destinations(org)`. Page `/jafar/texting-setup` (Operations area; sidebar count):
  number cards, To do queue, task panel (price step, Twilio tick with Copy ID, "I did it", Mark as turned on), done
  / "Sam already did this" results, Can't turn on pop-up. Business card `TextingCountriesCard` at the end of the
  org Communications tab: rows, Open task (`?task=`), ⋯ See it in Twilio / Turn off (asks first, reason).
- **5b-2 — next.** Waiting on Twilio, Countries & prices (Part 6) and Businesses tabs; the business tab's Email /
  Texting / Website chat switch with the Texting mode and Twilio account side cards (today's plain SMS cards stay).
  Not drawn yet, so ask Jafar before building: the card's **Add a country** pop-up and **Show its history**.
  Turning off does not email the business yet (the drawn pop-up promised it; copy says the business can ask again).
- **5c — needs a Pencil drawing first.** Contractor's "Text customers in another country" link (`NbWfA`) has no
  pop-up drawn; ask Jafar. Also show the WHERE YOU CAN TEXT box from destinations.
- **5d.** Opt-out words per language (Opt-out task in `v6Jtu`), recipient-local quiet hours.

## Proof so far

- 5b on the live app (localhost:5198, Raad LTD test business): marked US on → result + counts + sidebar badge;
  business card Ready "by Jafar"; Turn off; Can't turn on; "Sam already did this" (simulated teammate). A refresh
  under an open task once moved the panel to another task; fixed by pinning the worked task. Raad's BD and US are
  back to Setting up. `npx vitest run src/lib/jafar/texting-setup.spec.ts src/lib/jafar/team-access.spec.ts`: 28 pass.

- 5a, rolled-back live-DB runs: 6,798/6,800 numbers match libphonenumber; every route state; enqueue → claim;
  a turned-off country cancels and releases the hold.
- 5a vitest: 582 pass; `number-readiness.spec.ts` fails on main too (reported, not fixed).
- Twilio's GeoPermissions API answers 404 for our account, so switching on stays a dashboard step.
