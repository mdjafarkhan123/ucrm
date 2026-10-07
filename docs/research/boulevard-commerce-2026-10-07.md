# Boulevard commerce research (P2C)

**Checked 2026-10-07. Status:** evidence review complete. The agreed behavior is in the plan's
[Commerce](../boulevard-product-behavior-contract.md#commerce) section. This note keeps the sources,
vendor gaps, and reasons behind those rules. No release assignment or application work is implied.

Boulevard is the primary reference. Vagaro and Zenoti are used only where Boulevard leaves a necessary
workflow unclear or documents a weaker pattern. FTC material is current official US guidance, not legal
advice. State-specific review remains necessary before selling renewing plans or expiring paid value.

## Executive finding

Boulevard's model is clearest when each kind of prepaid value stays distinct:

- **Account credit** is money usable against any later purchase and does not expire.
- **A service voucher** pays for an eligible service and may have a disclosed expiry.
- **Prepaid product units** pay for measured product used during treatment, such as injectable units.
- **A deposit** secures one booking.

Boulevard collects a deposit for an appointment but then pools it with unrestricted account credit, including
credit granted by packages. Cancellation does not automatically refund it. The activity history remembers its
source, but the spendable balance is no longer reserved for the appointment. Our plan keeps the convenience of
a wallet while preserving the booking link.

## Confirmed Boulevard behavior

### Checkout, payment and order history

- Staff review the services actually performed, prices, products and gratuity, apply one or several payment
  sources, charge, and complete the order. Completion finalizes payment, appointment history and reporting.
  [Appointment checkout](https://support.boulevard.io/en/articles/5941386-appointment-checkout)
- Staff may add a performed service or change its price, add-ons and usage details during checkout.
  [Edit services at checkout](https://support.boulevard.io/en/articles/10414719-add-and-edit-services-at-checkout)
- Cash, cards, credit and other methods can split one total, but the full amount must be accounted for before
  the order closes. [Partial payments](https://support.boulevard.io/en/articles/5941430-partial-payments)
- Group checkout chooses a payer across several appointments. This does not make that payer the treated client
  or owner of every benefit used. [Group checkout](https://support.boulevard.io/en/articles/5941426-group-checkout)
- A same-day void reverses the whole order, requires permission and an explanation, remains in reporting, and
  may create a linked replacement. Later or partial returns use the refund flow instead.
  [Voiding orders](https://support.boulevard.io/en/articles/5941479-voiding-orders)
- Full and line-level partial refunds default to the original payment method. Staff record a reason, choose the
  physical-stock result where relevant, and choose whether commission is clawed back.
  [Issuing refunds](https://support.boulevard.io/en/articles/5941439-issuing-refunds)
- Completed purchases produce receipts that can be viewed later, resent, printed or saved. Text receipts follow
  transactional-message consent. [Receipts](https://support.boulevard.io/en/articles/5941488-receipts-sending-printing-and-saving)
- Open, closed, refunded and voided orders remain searchable. Unfinished orders must be resolved at closeout.
  [Orders and closeout](https://support.boulevard.io/en/articles/5941474-orders-and-closeout)

### Deposits, cancellation and account credit

- Account credit is money loaded on a client profile. The balance is all credits less debits, cannot expire,
  and can pay part or all of a later order. [Account credit](https://support.boulevard.io/en/articles/5941435-account-credit)
- Permissioned manual adjustments require a reason and create a tracking order with amount, staff member and
  source history. [Account-credit adjustments](https://support.boulevard.io/en/articles/5978297-account-credit-adjustments)
- An online deposit is a percentage configured per service or provider and is collected by card. Boulevard
  turns it into account credit; staff apply it manually at checkout. On reschedule it remains as credit. On
  cancellation it is not automatically refunded. Package credit and deposit credit share the same balance.
  [Pre-payments and deposits](https://support.boulevard.io/en/articles/5941467-pre-payments-and-deposits) ·
  [Packages](https://support.boulevard.io/en/articles/10015766-packages)
- A business sets a cancellation deadline and fixed or percentage fee capped at the appointment value.
  [Cancellation policies](https://support.boulevard.io/en/articles/5941349-cancellation-policies-and-fees)
- Only `Client late canceled` and `Client did not show up` expose a fee, and Boulevard never charges it unless
  staff deliberately choose to. The client receives the cancellation notice and fee receipt.
  [Canceling appointments](https://support.boulevard.io/en/articles/5941385-canceling-appointments)
- Boulevard does not document a dedicated rule that offsets a deposit against a cancellation fee.

### Memberships, packages, vouchers and units

- A membership renews on a configured cadence and can grant service vouchers, member discounts and unrestricted
  account credit after each successful cycle. Terms may include an agreement, commitment and cancellation
  notice. [Creating a membership](https://support.boulevard.io/en/articles/10012451-memberships-creating-a-membership-plan)
- Existing plan price and agreement changes apply to new sales. Boulevard's current and older pages conflict
  about when edited benefits reach current members, so explicit versioning is safer than silent change.
  [Updating memberships](https://support.boulevard.io/en/articles/8864471-updating-memberships)
- Retriable renewal failures are attempted on the renewal date and days 1, 2 and 5; terminal card failures are
  not retried. The client is told after each attempt and staff see the problem in daily work.
  [Membership billing](https://support.boulevard.io/en/articles/8619158-memberships-managing-billing)
- Boulevard may recover every missed term after reactivation or waive old terms and charge one current term.
  It requires a past-due membership to be reactivated before staff cancel it. Public material does not clearly
  say whether previously issued benefits remain usable while past due or paused.
- Staff can pause until a future resume date or cancel now/later. Future cancellation can be withdrawn before
  it takes effect; completed cancellation cannot. Discounts stop while paused or cancelled. Account credit
  remains, and unused vouchers remain until their configured expiry, possibly forever.
  [Membership billing](https://support.boulevard.io/en/articles/8619158-memberships-managing-billing) ·
  [Membership settings](https://support.boulevard.io/en/articles/11101465-membership-settings)
- A package is a one-time purchase granting service vouchers, unrestricted credit, or several perks. A voucher
  group uses `OR` logic; separate groups model a bundle containing several distinct services.
  [Packages](https://support.boulevard.io/en/articles/10015766-packages)
- Service vouchers pay for exact eligible services. A refund of a voucher-paid service restores the voucher.
  [Managing vouchers](https://support.boulevard.io/en/articles/5941364-managing-vouchers) ·
  [Vouchers as payments](https://support.boulevard.io/en/articles/9693255-vouchers-as-payments-before-and-after)
- Prepaid product units are a quantity balance used against configured product consumption. Refunding a unit
  redemption returns selected units; refunding or voiding the original unit sale deducts units.
  [Prepaid product units](https://support.boulevard.io/en/articles/10055190-prepaid-product-units)
- Same-day membership/package sale and redemption is deliberately two events: complete a retail-only purchase,
  issue the benefit, then redeem it at appointment checkout.
  [Same-day sale and use](https://support.boulevard.io/en/articles/12901962-selling-and-redeeming-a-membership-or-package-in-store-on-the-same-day)
- Boulevard does not document purchase refunds after some membership/package value was used, unit-sale refunds
  after some units were consumed, unit expiry/transfer, or same-day unit sale and use.

### Gift cards, offers, discounts and recorded payments

- Gift cards are a separate money balance sold online or in person and usable as partial payment. Sale,
  redemption, refund, adjustment and deactivation share one history. Balance changes are permissioned.
  [Gift cards](https://support.boulevard.io/en/articles/5941414-gift-cards-selling-applying-and-refunding) ·
  [adjustments](https://support.boulevard.io/en/articles/5941419-gift-cards-adjustments-deactivating)
- Named offers are rule-based promotions; manual discounts are staff price decisions with a reason. Both remain
  visible by line item. Boulevard stacks discounts automatically. Our plan makes stacking an explicit offer
  rule to prevent accidental over-discounting. [Offers](https://support.boulevard.io/en/articles/5941388-offers) ·
  [discounts](https://support.boulevard.io/en/articles/5941425-discounts)
- Custom payment types record money collected elsewhere; recording one does not process or verify it.
  [Custom payment types](https://support.boulevard.io/en/articles/5941387-custom-payment-types)
- Retail-only orders keep walk-in product sales separate from appointments and update stock after checkout.
  A later tip is a separate gratuity-only order attributed to its staff member.
  [Retail-only orders](https://support.boulevard.io/en/articles/5941464-retail-only-orders) ·
  [Gratuity-only orders](https://support.boulevard.io/en/articles/12860771-gratuity-only-orders)

## Competitor patterns used for gaps

- Vagaro places cancellation, deposit/prepayment refund and fee handling in one staff flow. A configured fee can
  be suggested while staff decide whether to charge it.
  [Vagaro cancellation fee](https://support.vagaro.com/hc/en-us/articles/360009686934-Cancel-Your-Customer-s-Appointment-and-Charge-a-Fee)
- Zenoti supports optional automatic collection for qualifying online cancellations. This establishes a later
  automation option, not a safe first-release default.
  [Zenoti online-booking configuration](https://help.zenoti.com/en/configuration/cma-configurations/configure-cma-v3-template--online-booking.html)
- Zenoti separates the date future billing ends from the date remaining benefits end, avoiding Boulevard's
  ambiguous pause/cancellation boundary.
  [Zenoti membership cancellation](https://help.zenoti.com/en/appointments/manage-guest-experience/manage-memberships/cancel-a-membership.html)
- Vagaro can refund a membership independently of restoring used visits; this can over-refund when the two
  actions are not coordinated. Zenoti instead supports a disclosed refund window and original-card return.
  [Vagaro membership refund](https://support.vagaro.com/hc/en-us/articles/18791547967515-Refund-a-Membership-and-Membership-Visits) ·
  [Zenoti refund window](https://help.zenoti.com/en/configuration/memberships-configurations/refund-membership-if-canceled-within-a-set-period.html)

## Settled pattern for our product

Jafar directed that a strong Boulevard rule should be adopted, a mature competitor should fill a documented
gap, and only an unresolved meaningful choice should return to him. Applying that direction:

1. Keep credit, appointment deposits, service vouchers, gift cards and product units separate and trace every
   use or reversal back to its source.
2. Reserve a deposit against its appointment. Move it with a reschedule; automatically refund a timely or
   business-caused cancellation to the original payment, unless the client deliberately chooses credit.
3. For late cancellation/no-show, calculate the disclosed fee, apply the deposit first, and let staff confirm or
   waive the charge with a reason. Automatic charging can be a later opt-in.
4. Never erase already-paid value because membership billing failed, paused or ended. Stop new perks and active
   discounts while unpaid or paused; previously paid value follows its disclosed expiry/refund rules.
5. Keep the billing-end date separate from the benefit-end date and let clients stop future renewal without
   first paying arrears.
6. Refund a partly used package or membership only up to its unused paid value by default. Show used value,
   remaining liability, revoked benefits and proposed refund; allow a permissioned goodwill exception.
7. Refund a prepaid-unit sale only for units still unused, at their actual paid unit value. Never create a
   negative unit balance. Refund of a treatment redemption restores the exact units reversed.
8. Allow same-day sale and use, but confirm purchase first and keep the issuance and redemption as two linked
   financial events inside one guided staff flow.
9. Never make another person's voucher usable merely because clients are checked out together. Require existing
   owner authorization or explicit owner consent recorded by staff.
10. Give online members a clear portal cancellation path and preserve the accepted terms, effective date and
    history. Price, cadence, commitment, notice, benefit-end and refund terms appear before payment.

## Current US renewal guidance and limits

The FTC's 2024 amended negative-option rule was vacated in July 2025. In March 2026 the FTC began a new
rulemaking process; it is not a settled nationwide replacement. Existing federal protections still require
truthful material terms, informed consent and a simple way to stop recurring online charges, while state laws
vary. [FTC 2026 negative-option rulemaking](https://www.ftc.gov/system/files/ftc_gov/pdf/p064202negativeoptionruleanprm.pdf)

Public sources establish visible vendor behavior, not Boulevard's private ledger, processor design, legal
sufficiency, or every state rule. Before launch in a state, renewing-plan terms, cancellation and paid-value
expiry require state-specific review. Release assignment and existing-app suitability remain P3 decisions.
