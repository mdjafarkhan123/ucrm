# P11a — Offer rules (database)

**Campaign:** package-builder · **Plan:** `docs/package-builder-behavior-contract.md` § Prices and offers
**Code:** `main`
**Done when:** see the P11a line in `stages/3-customers.md`

## Steps

- [ ] Migration: offers, eligible packages, claims; agreement links its claim; discounted charge pricing
- [ ] Change package: offer by pick or code, keep tick box; activation: snapshot offer, warn, honor or normal price, or a code
- [ ] Public readers and application snapshot carry the automatic offer
- [ ] Database checks for the done-check; push; server types and callers updated

## Next

Write the migration `supabase/migrations/20261001140000_introductory_offers.sql`.

## Notes

Jafar's answers, 2026-09-30:
- A spot counts when Jafar activates (or confirms a change), not when the visitor applies. If the offer stopped being claimable in between (cap, deadline, archived), activation warns and Jafar chooses: honor it anyway or normal price.
- Existing customers get an offer through Change package (pick an eligible offer or type a code; the same package may be kept just to add an offer). The offer months start with the change.
- Keeping an offer on a package change is a tick box, off by default, allowed only when the billing interval stays the same; it keeps the original end date.

Design choices (industry: Stripe coupons and promotion codes): discount terms are fixed once claimed, while name, dates, cap, and archive stay editable. Each organization claims an offer at most once. A new offer's months start at the first full period of the change. A charge is discounted when its period starts inside the offer window, and a part-period charge is prorated from the discounted price.
