# Package pricing and introductory offers

Researched 2026-09-29. Monthly and yearly pricing and introductory offers are requested; detailed rules below are recommendations awaiting approval. No billing provider has been selected.

## Established patterns

- Separate the package from its monthly and annual prices. New amounts use new prices; archived prices can retain existing subscriptions. [Stripe prices](https://docs.stripe.com/products-prices/manage-prices).
- Percentage and fixed discounts can be applied directly or through promotion codes. Eligibility, redemption limits, and duration are separate controls. Removing a coupon prevents future applications without removing existing discounts. [Stripe coupons](https://docs.stripe.com/billing/subscriptions/coupons).
- A claim deadline is separate from the duration of a redeemed benefit. [Chargebee validity and duration](https://www.chargebee.com/docs/billing/2.0/kb/product-catalog/how-is-coupon-validity-different-from-coupon-duration).
- A months-long Stripe coupon can discount a whole annual invoice issued within its window. Monthly introductory wording must therefore not be reused blindly for annual billing. [Stripe duration](https://docs.stripe.com/billing/subscriptions/coupons#coupon-duration).
- Stripe's API reference marks repeating duration fields deprecated even though its guide describes them. Confirm the supported integration when a provider is chosen; do not tie the product contract to these fields. [Stripe coupon API](https://docs.stripe.com/api/coupons).

## Proposed rules

Set monthly and yearly normal prices independently. Support percentage or fixed reductions, three/six-month presets and a configurable number of introductory monthly periods. Annual offers explicitly discount the first year. Allow package/interval eligibility, new-customer restrictions, claim dates, redemption caps, and optional codes. Apply one promotion at a time. Show both introductory and subsequent prices, and preserve each customer's agreed terms when public offers change.

Annual upfront payment versus monthly installments, currencies, and these detailed promotion rules await decisions. Before billing implementation, settle partial periods, failed payments, trials, refunds, early cancellation, and changes of package or billing interval during a promotion. Returning to an agreed normal price after an agreed promotion is distinct from moving the customer to a newer package edition.
