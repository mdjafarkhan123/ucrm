# Online Payments — Behavior Contract

Status: **Approved by Jafar 2026-09-18** with all four decisions as recommended (tips off by default, refunds from
inside UCRM, per-invoice partial online payments off by default, add Venmo/Zelle/Cash App/e-Transfer; no money
order). Pay-by-app work comes after the Stripe parts. This is the source of truth for the
online-payments campaign (`Memory/campaigns/online-payments/`).

## Why it works this way

- UCRM's owner is in Bangladesh, and Stripe does not support Bangladesh. "Connect with Stripe" one-click
  setup (Stripe Connect or a Stripe App) needs the software company itself to own a Stripe account, so it
  is not possible today.
- So each contractor uses **their own Stripe account** and pastes **one key** into UCRM. Money goes straight
  from the customer to the contractor's Stripe account, then to their bank. UCRM never holds money.
- Venmo, Zelle, Cash App, PayPal and Interac e-Transfer have no system UCRM can connect to for this.
  Like Jobber, UCRM shows the contractor's details so the customer can pay them, and the contractor then
  records the payment.
- Future option (not in this campaign): if Jafar forms a US company, UCRM can add true one-click Stripe
  Connect and earn a small fee per payment.

## Sources and industry pattern followed

- Jobber Payments: pay online from the invoice, quote deposits online, per-invoice partial payments
  ("Allow client to make partial payments for this invoice", default off, not for progress invoices),
  tips of 10/15/20% or a custom amount calculated on the pre-tax subtotal and kept separate from the invoice
  total, automatic client receipts, owner alerts when a payment arrives, and Venmo/Zelle/Cash App/
  e-Transfer as recorded payment types.
  Sources: [Jobber Payments Basics](https://help.getjobber.com/hc/en-us/articles/115009571387-Jobber-Payments-Basics),
  [Payment Settings](https://help.getjobber.com/hc/en-us/articles/115009590727-Manage-your-Jobber-Payments-Settings),
  [Tips](https://help.getjobber.com/hc/en-us/articles/4410192275479-Tip-Collection-with-Jobber-Payments),
  [Collect Payment](https://help.getjobber.com/en/articles/how-to-collect-payment-on-an-invoice/),
  and the `PaymentType` list in `.claude/skills/jobber/jobber-05-invoices-payments.md` §5.3.
- Housecall Pro: a Payment Methods setting that applies to every future invoice.
- Stripe: restricted keys (least privilege), hosted Checkout pages (Stripe handles the card form, Apple
  Pay, Google Pay and bank payments), and signed webhooks.
  [Restricted keys](https://docs.stripe.com/keys/restricted-api-keys).
- ContractorOs (Jafar's earlier app) used the same own-Stripe-account idea. It needed 3 pasted values and
  a manual webhook setup. UCRM cuts this to 1 pasted value.

## 1. Connecting Stripe (contractor side)

- **Where:** Settings → Payments. Only the account owner and admins can connect, change or disconnect
  Stripe.
- **The contractor's steps:**
  1. Create a free Stripe account and finish Stripe's identity and bank checks. The guide links straight to
     Stripe.
  2. In Stripe, create a **restricted key** named "UCRM" with the permissions the guide lists (the guide
     shows each one with a screenshot).
  3. Paste the key into UCRM and click **Connect**.
- **What UCRM does on Connect, automatically:** checks the key works, reads the Stripe business name and
  whether it's in test or live mode, creates the "payment happened" notification link (the webhook) inside
  the contractor's Stripe account, and stores everything encrypted.
- **After saving,** the key is never shown again, and never goes to the browser or to Jafar. The screen shows
  "Connected as <Stripe business name> · Live (or Test) · last checked <time>".
- **Test mode:** a test key (`rk_test_…`) works too. The contractor can make a practice payment with a
  Stripe test card before going live, and invoices clearly say "Test mode — no real money".
- **Replace key / Disconnect:** replacing the key re-checks it and resets the webhook. Disconnecting
  immediately hides every Pay button. Payments that already went through stay recorded.
- **Help:** the guide ends with "Stuck? We'll set it up with you". The contractor books a free call, and
  Jafar helps over UltraViewer. **Security rule for assisted setup:** the contractor pastes the key themselves.
  Keys are never sent by chat, email or SMS.

## 2. Payment settings the contractor controls

| Setting | Default | Meaning |
| --- | --- | --- |
| Accept online payments on invoices | On once Stripe is connected | Shows a Pay button on invoices |
| Accept online quote deposits | On once Stripe is connected | Shows "Pay deposit" when a quote requires one |
| Allow tips | Off | Customer can add 10/15/20% or a custom tip |
| Email receipt automatically | On | Customer gets a receipt after paying online |
| Pay-by-app details | Empty | Venmo, Zelle, Cash App, PayPal, e-Transfer, bank transfer instructions |

Payment types (card, Apple Pay, Google Pay, US bank/ACH, UK/EU bank debits) are switched on by the
contractor **inside Stripe**. UCRM shows whatever Stripe allows for that customer's country and currency.
This keeps UCRM simple and works in every launch country.

## 3. Customer pays an invoice online

- The customer's invoice page (link from email or SMS) shows a green **Pay** button while money is owed and
  online payments are on.
- **Amount:** the full balance by default. If the contractor turned on "Allow partial payments" for that
  invoice, the customer can type a smaller amount. That option isn't offered on progress (staged) invoices,
  same as Jobber.
- **Tip** (if allowed): 10/15/20% of the pre-tax subtotal, or a custom amount. The tip is kept separate:
  it doesn't change the invoice total or balance.
- Clicking Pay opens Stripe's secure payment page in the invoice's currency. After paying, the customer
  returns to the invoice, which says "Payment received — thank you" once Stripe confirms.
- **Invoices are only marked paid after Stripe confirms the payment.** A payment counts once, even if
  Stripe sends the same notification several times.
- **Bank payments take days.** The invoice shows "Payment processing" and doesn't count the money until
  Stripe confirms it. If the bank payment fails, the balance stays owed and the contractor is alerted.
- **Safety:** before sending the customer to Stripe, UCRM re-checks that the business is active, Stripe is
  still connected, and money is still owed. If a payment would overpay (for example, someone paid by cash
  at the same moment), UCRM doesn't apply the extra money and warns the contractor to refund it in Stripe.
- **After payment:** it appears on the invoice's and client's payment history as "Card (online)", or as
  the bank method. The contractor gets an in-app notification, the customer gets a receipt if that setting
  is on, and all open screens update.

## 4. Customer pays a quote deposit online

- On a quote that requires a deposit, after approving and signing, the customer sees **Pay deposit**, which
  opens the same Stripe flow for the exact required deposit amount.
- A confirmed deposit payment counts as the deposit, so the quote becomes ready to turn into a job, exactly
  like a recorded deposit does today.

## 5. Refunds and disputes

- The contractor refunds from UCRM ("Refund" on a Stripe payment, full or part). UCRM asks Stripe to send
  the money back, and records the refund once Stripe confirms. Refunds made directly in Stripe's dashboard
  are also picked up automatically.
- A **dispute (chargeback)** creates an urgent alert for the contractor with a link to respond in Stripe.
  UCRM doesn't try to handle the dispute itself.

## 6. Venmo, Zelle, Cash App, PayPal, e-Transfer

- In Settings → Payments, the contractor fills in only what they use: Venmo @username, Zelle email or
  phone, Cash App $cashtag, PayPal.me link, Interac e-Transfer email, and free-text bank transfer details.
- The customer's invoice and deposit pages show a **"Other ways to pay"** box. Venmo, Cash App and PayPal
  are tappable links that open the app. Zelle and e-Transfer show the email or phone with a copy button.
- These payments are **recorded, not processed.** The contractor clicks "Record payment" and picks the
  method. The method list adds **Venmo, Zelle, Cash App, e-Transfer** to today's six methods.

## 7. Jafar (platform owner) view

- Per business: Stripe connected or not, business name, test/live, last successful check, webhook health,
  and any recent payment problems in plain words. Jafar never sees keys.
- Jafar can pause online payments for a suspended business. Suspension or closure automatically hides Pay
  buttons.

## Not included (proposals for later)

Saved cards and auto-pay, card readers and tap-to-pay, adding a card fee for customers (surcharges; rules
differ by country and US state), consumer financing, payout reports, and automatically turning cards off
above an amount.

## Decisions for Jafar

All rows above are the recommendation. Please confirm or change these four:

1. **Tips** are available but **off by default**. (Jobber turns them on by default only for some trades.)
2. **Refund from inside UCRM** is included. The alternative is only reflecting refunds made in Stripe, which
   is less work but less easy for the contractor.
3. **Partial online payments** are allowed per invoice, off by default, like Jobber.
4. **New recorded methods:** Venmo, Zelle, Cash App, e-Transfer. Money order is left out unless you want it.
