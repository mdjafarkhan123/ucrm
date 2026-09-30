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
- [ ] Activation dialog UI in `src/routes/jafar/(protected)/prospects/+page.svelte`
- [ ] API tests for the offer routes; browser check of the done-check

## Next

In the prospects page's activation `ConfirmDialog` (search `confirmingProvision`): add state for offer decision and typed code (reset in `openProvisionConfirm`); add both to the activation query key and to `loadActivation`'s URL (`offer_decision`, `offer_code`); show an "Intro offer" row (terms and first charge from `activation.offer.terms` / `first_charge_usd_cents`); when `activation.offer.source === 'shown'` and it has problems, offer Honor / Normal price; otherwise a code input with Apply. The `provisionOrganization` mutation must send `offer_decision`, `offer_code`, and `expected_first_charge_usd_cents: activation.first_charge_usd_cents`. Imported but still unused there: `offerDiscount`, `offerLength`.

## Outside actions

- Migration `20261001150000_scheduled_change_shows_offer` — check: `supabase migration list --linked` shows it remote — done

## Notes

- Tiny edge: if an offer closes between a visitor loading `/get-started` and submitting, the application records no offer. Mention to Jafar at the browser check.
