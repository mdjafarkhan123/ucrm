# Stage 10 Parts 2 + 3 — Buy a number, and its paperwork

**Campaign:** communications-activation · **Plan:** `docs/global-sms-behavior-contract.md` § Part 2, § Part 3
**Stage:** Building · **Branch / folder:** `claude/stage10-parts23` in `.worktrees/stage10-parts23` (pushed)
**Claim:** `4e0ad188b841` (owner `claude-stage10-opus`) — keep until merged.
**Done when:** a business can buy a texting number from Add number (board `qaFQf`) and send country paperwork
(board `A0URqF`), every state matches its board, then merged to main.

## Part 2 — built 2026-10-22 (not merged)

- DB (applied live): `20261222120000_sms_number_purchase.sql`, `20261222120100_sms_number_order_claim.sql` — Jafar's
  versioned number prices (`communication_sms_number_retail_rates`), number orders that hold the first charge, charge
  once on Twilio's confirmation, release on refusal; single-winner purchase claim; sender gets `number_type` and
  `provider_phone_number_sid`. Numbers are paid from the bought balance only, never promotional credit.
- Server: `sms-number-purchase.ts` (resumable saga; reconciles an interrupted buy via `findOwnedPhoneNumber` after a
  60 s window), `sms-number-purchase-store.ts`, `sms-number-shop.ts`, Twilio calls in `twilio.ts`
  (`createTwilioNumberPurchaseClient`), `getSubaccountAccess` in `twilio-provisioning.ts`. First purchase provisions
  the subaccount if missing.
- API: `/api/settings/communications/sms/{number-countries, number-countries/[countryCode], available-numbers,
  number-orders}`; Jafar: `/api/jafar/communications/sms/number-rates` (GET/POST).
- UI: `src/lib/components/communications/add-number/*`, Add number button on Phone & SMS header; `CountryPicker`
  gained `only`; `Dialog` gained `closeDisabled`.
- Proof: 15 saga tests + CountryPicker tests pass (20). Live 1440 light/dark walk of steps 1–3 against live Twilio
  stock, nothing bought (temporary US prices added for the check and deleted; 0 orders exist).

## Open items (Part 2)

- **No number prices exist.** Every kind shows "Uplift is setting its price" until Jafar sets them (Part 6's
  Countries & prices tab; API exists now). Ask Jafar for US local / toll-free selling prices.
- **Monthly renewal is not built** (only first month + setup charged). Needs research (GHL wallet renewal, what
  happens when the balance can't pay) and Jafar's decision before any live purchase.
- A sweep for orders stuck "purchasing" when the pop-up is closed mid-check (money stays held) — small cron.
- Bought-view and refusal states not yet screenshotted (need a real buy; never without Jafar's yes).
- Not drawn, built by settled rules: "Uplift is setting its price" band + notice; non-US bought notice.

## Next

Part 3 (paperwork): ledger tables like `trust-hub-submission-store.ts`, Twilio create → link → evaluate → submit,
R2 documents, webhook + daily check; Number paperwork list/form pages (board `A0URqF`) at
`/settings/communications/sms/paperwork` (Add number's "Start paperwork" already links to `/paperwork/new?country&type`);
replace `noApprovedPaperwork` in `sms-number-purchase.ts` with the approved-bundle lookup.
