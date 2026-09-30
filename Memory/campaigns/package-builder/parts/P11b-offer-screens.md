# P11b — Offer screens

**Campaign:** package-builder · **Plan:** `docs/package-builder-behavior-contract.md` § Prices and offers
**Code:** `main`
**Done when:** Browser check: build the $149 offer, see it on the card and `/get-started`, activate an application with it, and see the first charge at $74.50

## Steps

- [x] Offer builder: "Introductory offers" section under Jafar's Packages page (`PackageOffersSection`, `PackageOfferDialog`), API `/api/jafar/package-offers` (+ `[offerId]` PATCH save/archive/restore)
- [x] Public: offer on `PackageCard`, `PackageDetails`, `/packages/[slug]` hero, `/get-started` review and details (data from `public_package_offers` in `loadPublicPackages`)
- [x] Change package dialog: Offer box (automatic list, "Enter a code…", keep tick box, off by default); preview and command carry `offer_id`, `offer_code`, `keep_offer`
- [x] Billing tab shows the running offer and the scheduled change's offer (migration `20261001150000`)
- [x] Activation APIs accept `offer_decision`, `offer_code`, `expected_first_charge_usd_cents`; prospects page types and payment hints use the intro price
- [x] Activation dialog UI in `src/routes/jafar/(protected)/prospects/+page.svelte`
- [x] API tests for the offer routes (`package-offers.spec.ts`)
- [ ] Browser check of the done-check

## Next

Run the browser check in the done line: build the offer on Jafar's Packages page, look at the package card and `/get-started`, then activate a test application with it and confirm the first charge is half the price.

## Outside actions

- Migration `20261001150000_scheduled_change_shows_offer` — check: `supabase migration list --linked` shows it remote — done

## Notes

- Tiny edge: if an offer closes between a visitor loading `/get-started` and submitting, the application records no offer. Mention to Jafar at the browser check.
