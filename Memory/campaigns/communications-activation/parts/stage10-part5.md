# Stage 10 Part 5 — Sending rules per country

**Campaign:** communications-activation · **Plan:** `docs/global-sms-behavior-contract.md` § Part 5
**Stage:** 5a built. 5b and 5b-2's first two pieces built 2026-10-23, **Waiting to merge** on branch
`claude/stage10-part5b` (main held by the Pencil tidy session, `19503cc6bd58`). Rest of 5b-2, 5c, 5d not started.
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
- **5b-2 — partly built.** Done: the business tab's Email / Texting / Website chat switch (`?channel=texting`),
  `TextingSideCards` (Texting mode: Uplift override + reason only, replaces `SmsModeActions`; Twilio account via
  `sms/twilio-account`), and the Waiting on Twilio tab (`waiting`, `waiting/check` → shared `runTwilioReviewChecks`).
  Left: **Countries & prices** (Part 6), planned 2026-10-23 against `R6mF2`/`dc8G7` in `v6Jtu`:
  (1) table `communication_sms_twilio_prices` — Twilio cost per country, sender type and unit (segment, picture,
  number month, setup), with `checked_at`; a check that moves a cost keeps the old row so the notice can say
  from → to and the margin change. Read through `twilio-country-catalog.ts` (already reads Pricing API).
  (2) Owner route listing one row per country: Twilio cost, their price (`communication_sms_retail_rates` +
  `communication_sms_number_retail_rates`), margin, picture, number a month, businesses using it
  (`communication_sms_destinations`), status, any price starting later. (3) Check Twilio prices (route + button,
  spins). (4) Change price pop-up: segment, picture and number prices, Now or On a date, new rate versions only.
  (5) Price-moved notice with Review price. (6) Remove the old SMS retail rates list. Jafar 2026-10-23: **Add a country**
  reuses the Change price pop-up with a country picker; **Show its history** and the **Businesses** tab later;
  status **Off** = Uplift doesn't offer the country (no new requests; businesses already texting there keep it
  until turned off one by one). Turning off does not email yet.
  **Countries & prices — first draft built 2026-10-23, not yet checked.** Migration `20261231120000_sms_country_prices`
  **applied** (tables, `communication_sms_price_list`, `_set_country_price`, `_set_country_offered`,
  `_record_twilio_prices`; request refuses an Off country). Routes `api/jafar/texting-setup/prices` (+ `check`,
  `[country]/offered`); `CountriesPrices.svelte`, `ChangePriceDialog.svelte` (also Add a country and the task
  panel's price step); MoneyInput `decimals`, Dialog `lead`, CountryPicker `except`; old `SmsRetailRateActions`
  removed. **Next:** svelte-check these files (`--max-old-space-size=10240`; it was interrupted), svelte-autofixer,
  a unit test for `twilioPriceRows`, then a live Chrome check of the tab and pop-up against `R6mF2`/`dc8G7`.
- **5c — needs a Pencil drawing first.** Contractor's "Text customers in another country" link (`NbWfA`) has no
  pop-up drawn; ask Jafar. Also show the WHERE YOU CAN TEXT box from destinations.
- **5d.** Opt-out words per language (Opt-out task in `v6Jtu`), recipient-local quiet hours.

## Proof so far

- 5b-2 live (Raad LTD): Texting view, Force off + reason saved and shown (test row then removed); Waiting tab,
  Check now → "Last asked just now"; cron route spec 6 pass.
- 5b live (Raad LTD): mark on, Turn off, Can't turn on, "Sam already did this"; Raad's BD and US back to Setting
  up. `texting-setup.spec.ts` + `team-access.spec.ts`: 28 pass.

- 5a, rolled-back live-DB runs: 6,798/6,800 numbers match libphonenumber; every route state; enqueue → claim;
  a turned-off country cancels and releases the hold.
- Twilio's GeoPermissions API answers 404 for our account, so switching on stays a dashboard step.
