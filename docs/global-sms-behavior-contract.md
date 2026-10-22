# Global texting behavior contract (the GoHighLevel way)

## Context

Jafar wants texting to work for contractors in every country, copying GoHighLevel (GHL) exactly.
There is no registered business yet, so the goal is a launch-ready app now. The real end-to-end test waits for
the first paying customer.

Today the app texts for **US contractors only**:
- the registration country is fixed to `US` (`src/lib/server/communications/sms-registration.ts:7`, and the
  settings page at `src/routes/(app)/settings/communications/sms/+page.svelte:113`);
- only US A2P 10DLC registration exists (`trust-hub-submission.ts`), and nothing in the app calls it yet;
- the app has no way to search for or buy numbers (`twilio-provisioning.ts` only attaches an already-bought number);
- there is no paperwork flow for countries outside the US and Canada.

Sending, replies, opt-outs, the balance, the inbox and Automation already work for any country.

### How GHL does it (from GHL's own help pages)

- **Countries:** GHL publishes no fixed list. Its phone system (LC Phone) runs on Twilio's platform-for-other-
  businesses (ISV) model, which is our setup too. A business can buy a number in any country where Twilio sells
  one. The country picker shows Twilio's live stock, and prices follow Twilio's prices for each country.
  Sources: [Purchase a number](https://help.gohighlevel.com/support/solutions/articles/155000003226),
  [LC Phone pricing](https://help.gohighlevel.com/en/support/solutions/articles/48001223556).
- **Buying a number:** Settings → Phone System → Add Number → pick a country → filter by local or toll-free and
  by SMS/MMS/voice → see the monthly price → buy.
- **Paperwork:** "Regulatory Bundle / Address" lives in each business's own Phone System settings. The business
  picks the country and number type, fills in business and representative details, uploads the requested
  documents and submits for review. GHL says the requirement shown at purchase is the source of truth, and it
  gives no fixed review time. Source: [Regulatory Bundle](https://help.gohighlevel.com/support/solutions/articles/48001213216).
- **US/Canada:** no paperwork to buy a number. After buying, US local numbers need 10DLC registration, and
  toll-free numbers need Toll-Free Verification. GHL also runs an identity check (Persona) before a +1 number
  can be bought.
- **Sending countries:** each business has a list of countries it may text. Sending to a country that isn't
  switched on is refused. Source: [LC Phone error codes](https://help.gohighlevel.com/support/solutions/articles/155000005526).
- **Countries with no texting numbers (for example New Zealand and Brazil):** this is a phone-company rule, not
  something GHL chose. The number list simply shows no texting-capable numbers there. Those businesses use
  WhatsApp instead (a separate later channel).
  Evidence: `docs/research/global-sms-country-requirements-2026-10-22.md`.

Following GHL settles last session's six questions:
- countries: every country with Twilio stock (no app-level block; Jafar does not sell subscriptions in Asia);
- number types: whatever Twilio sells in that country;
- paperwork: our own in-app form;
- prices: Twilio's price for each country plus our margin;
- New Zealand and Brazil: no texting, WhatsApp later.

## Approach

**Always read the rules live from Twilio, never write them into our code** (Twilio's own warning, and GHL's
"source of truth at purchase"). Our code stays general, so a new country works without a code change.

### Part 1 — Country rules and the platform profile
- Save the approved platform profile ID `BU0a5a8f75e733bf8f1020e8d923a017f5` and the monitoring email as server
  settings in `src/lib/server/env.ts`.
- Build one server module that asks Twilio live what each country offers:
  - number types and whether each can text, send pictures or take calls (the AvailablePhoneNumbers API);
  - the paperwork each needs (the Regulations API).
- Keep a short cache.
- The country list is every country Twilio sells numbers in. The app blocks no region: Jafar controls who can use
  texting by who he sells subscriptions to (Jafar, 2026-10-22).

### Part 2 — Contractor buys a number (like GHL's Add Number)
- Phone & SMS settings gets an "Add number" dialog:
  - pick a country (the existing country picker), number type and abilities;
  - see numbers with their monthly price;
  - buy.
- Server: search and buy in the contractor's own Twilio subaccount. Then reuse the existing attach step in
  `twilio-provisioning.ts` to join the Messaging Service and create the sender record. The sender table already
  has `country_code`, `sender_type` and the ability columns.
- Every purchase is idempotent (it cannot buy twice), shows a loading state, and is audited.

### Part 3 — Paperwork (Regulatory Bundle / Address), like GHL's Compliance area
- A "Compliance" section in Phone & SMS settings:
  - create a bundle for a country and number type;
  - the form fields are built from Twilio's live requirements;
  - documents go to R2;
  - submit, see the status, fix and resubmit when rejected.
- Server: Twilio's create → link → evaluate → submit sequence, stored in a ledger like the existing Trust Hub
  ledger (`trust-hub-submission-store.ts` pattern).
- Status updates come by webhook, with a daily check as a safety net. This reuses the
  `trust-hub-status-poll-cron.ts` pattern.
- The purchase in Part 2 asks for an approved bundle or address whenever Twilio requires one.

### Part 4 — Registration per number, not per country
- Remove the fixed `US` and register per sender:
  - **US local:** the existing 10DLC flow, finally wired to a "Submit" action;
  - **US/Canada toll-free:** a new Toll-Free Verification flow (Twilio API) that reuses the contractor's already
    collected business answers;
  - **Canada local:** no 10DLC for Canadian customers;
  - **Other countries:** the approved bundle is enough.
- The readiness strip shows what each number still needs.

### Part 5 — Sending rules per country
- An allowed-countries list for each contractor. Home country is on by default, others can be switched on.
  Sends to a country that isn't on are refused at enqueue (`sms-estimate` and the enqueue command).
- Picture messages follow each number's own picture ability instead of a fixed US/CA list
  (`sms-estimate/+server.ts:76`). Where pictures can't be sent, Twilio's converter sends a link instead.
- Twilio's Advanced Opt-Out handles STOP words in other languages. Quiet hours follow the customer's country.

### Part 6 — Prices per country
- Retail rates are already stored by destination. Add per-country number and text prices: Twilio's price plus
  our margin, set in Jafar's existing rate controls.

### Not in this build (later, recorded as deferred)
- GHL's paid identity check (Persona) before +1 numbers.
- WhatsApp for countries without texting numbers.
- Moving an existing number in from another provider (porting).

## Order and design
1. Pencil designs come first, per the design skill: the Add number dialog, the Compliance list and form, the
   per-number readiness, and Jafar's country controls. Jafar approves them, then they get built.
2. Part 1 is the server foundation.
3. Parts 2 and 3 run together, because a purchase needs the paperwork.
4. Then Part 4, then Parts 5 and 6.

## Verification (no money spent)
- Unit tests against fake Twilio replies for every new flow (vitest, like `twilio-trust-hub.spec.ts`).
- Read-only live Twilio calls prove real country data loads: number search and requirements for the US, Canada,
  the UK, Australia, Germany and Brazil. Nothing is bought.
- Browser check in Chrome at 1440 wide, in light and dark: search shows real numbers and prices, the paperwork
  form shows the UK's real fields, New Zealand and Brazil show "no texting numbers".
- Real purchase, registration and a live text wait for the first paying customer, with Jafar's yes.

## For Jafar to do
- Ask Twilio support one question: does our Bangladesh-registered platform profile cause any problem for US
  10DLC registration of our customers? Twilio's guide has one unclear sentence about this.

## Approval record

Jafar approved this plan on 2026-10-22 ("follow GHL totally"; every country Twilio supports; no region blocked in the app — Jafar simply does not sell to Asia).
Each new screen still needs its Pencil design approved before it is built.
