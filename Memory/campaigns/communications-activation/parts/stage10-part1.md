# Stage 10 Part 1 — Country rules and the platform profile

**Campaign:** communications-activation · **Plan:** `docs/global-sms-behavior-contract.md` § Part 1
**Stage:** Built and verified 2026-10-22 · **Done when:** the server can read, live, every in-stock country's
number types and abilities, paperwork and prices, and holds Uplift's ISV settings.

## What exists

- `src/lib/server/communications/twilio-country-catalog.ts` — read-only Twilio adapter: in-stock countries
  (AvailablePhoneNumbers), number search, paperwork (Regulations v2, `IncludeConstraints`), number and message
  prices (Pricing v1, `current_price`, exact decimal strings). Normalizes Twilio's three toll-free spellings and
  both capability-key spellings; 404 = no stock / no prices; never follows a next page to another host.
- `src/lib/server/communications/sms-country-catalog.ts` — 10-minute in-process cache (failures and number
  searches never cached; concurrent callers share one request) and per-type abilities (`listNumberTypeOptions`:
  text / pictures / calls). `getSmsCountryCatalog()` is the shared instance. No API route yet — Part 2 adds them.
- `src/lib/server/env.ts` — `TWILIO_ISV_PRIMARY_PROFILE_SID` (set in main `.env` to `BU0a5a…17f5`) and
  `TWILIO_ISV_MONITORING_EMAIL` (unset: waits for Jafar).

## Proof

- `npx vitest run src/lib/server/communications/{twilio-country-catalog,sms-country-catalog}.spec.ts` — 27 pass.
- Live read-only run 2026-10-22 (nothing bought): 53 countries in stock; US/CA local + toll-free text with no
  paperwork; GB/DE landlines voice-only, mobiles text; Brazil voice-only (matches research); AU/DE/GB paperwork
  fields and documents read; cached repeat 0 ms. Type check deferred to campaign end (memory rule).
