# Global texting behavior contract (the GoHighLevel way)

## Context

Jafar wants the GoHighLevel (GHL) texting experience wherever the required behavior is supported: choose a
number, complete required business details, follow approval progress, then text in the inbox. Uplift handles
Twilio and provider setup behind the scenes; contractors never need their own Twilio account or dashboard.
There is no registered business yet, so the goal is a launch-ready app now. The real end-to-end test waits for
the first paying customer.

Today the app texts for **US contractors only**:
- the registration country is fixed to `US` (`src/lib/server/communications/sms-registration.ts:7`, and the
  settings page at `src/routes/(app)/settings/communications/sms/+page.svelte:113`);
- only US A2P 10DLC registration exists (`trust-hub-submission.ts`), and nothing in the app calls it yet;
- the app has no way to search for or buy numbers (`twilio-provisioning.ts` only attaches an already-bought number);
- there is no paperwork flow for countries outside the US and Canada.

Sending, replies, opt-outs, the balance, the inbox and Automation already exist and should be reused. Their
existence does not establish that every country or sender-to-destination route is ready for activation.

### How GHL does it (from GHL's own help pages)

- **Countries:** GHL publishes no fixed list. Its phone system (LC Phone) runs on Twilio's platform-for-other-
  businesses (ISV) model, which is our setup too. Businesses search supported countries and number types. HighLevel documents country, capability and inventory-dependent availability. Uplift uses
  its own Twilio account's live inventory; identical availability between providers is not assumed.
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
  WhatsApp as a possible separate later channel; Uplift does not offer that fallback in this build.
  Evidence: `docs/research/global-sms-country-requirements-2026-10-22.md`.

Following GHL settles last session's six questions:
- countries: every country with Twilio stock (no app-level block; Jafar does not sell subscriptions in Asia);
- number types: whatever Twilio sells in that country;
- paperwork: our own in-app form;
- prices: Twilio's price for each country plus our margin;
- New Zealand and Brazil: no texting, WhatsApp later.

## Approach

**Read number inventory, purchase paperwork and provider prices live from Twilio.** Twilio warns against
hardcoding regulatory-bundle requirements. Its Regulations API describes purchase paperwork, not every
messaging, consent or destination rule. Reuse a general discovery flow, then verify applicable sender and
destination rules before activation; a newly listed country is not automatically ready.

Uplift adapts GHL's documented customer journey. The provider corrections below are part of the approved
agreement, not optional contractor settings. Sources: [Twilio Regulations](https://www.twilio.com/docs/phone-numbers/regulatory/api/regulations),
[Geo Permissions](https://www.twilio.com/docs/messaging/guides/sms-geo-permissions),
[Advanced Opt-Out](https://www.twilio.com/docs/messaging/tutorials/advanced-opt-out).

### Part 1 — Country rules and the platform profile
- Save the approved platform profile ID `BU0a5a8f75e733bf8f1020e8d923a017f5` and the monitoring email as server
  settings in `src/lib/server/env.ts`.
- Build one server module that asks Twilio live what each country offers:
  - number types and whether each can text, send pictures or take calls (the AvailablePhoneNumbers API);
  - the paperwork each needs, including end-user type (the Regulations API);
  - account-specific number and message prices (the separate Pricing APIs).
- Keep a short cache.
- The country list is every country Twilio sells numbers in. The app blocks no region: Jafar controls who can use
  texting by who he sells subscriptions to (Jafar, 2026-10-22).

### Part 2 — Contractor buys a number (like GHL's Add Number)
- Phone & SMS settings gets an "Add number" dialog:
  - pick a country (the existing country picker), number type and abilities;
  - see numbers with their capabilities, final monthly selling price and applicable setup charges;
  - buy.
- Server: search and buy in the contractor's own Twilio subaccount. Then reuse the existing attach step in
  `twilio-provisioning.ts` to join the Messaging Service and create the sender record. The sender table already
  has `country_code`, `sender_type` and the ability columns.
- Every purchase is idempotent (it cannot buy twice), shows a loading state, and is audited. Reconcile an
  interrupted purchase with Twilio before retrying so neither a second number nor duplicate charge is created.
- Explain provider outages, empty stock and no supported texting-number option distinctly. Voice-only numbers
  are never shown as texting-ready.

### Part 3 — Paperwork (Regulatory Bundle / Address), like GHL's Compliance area
- A "Compliance" section in Phone & SMS settings:
  - create a bundle for a country and number type;
  - the form fields are built from Twilio's live requirements;
  - documents go to private, organization-isolated R2 storage;
  - reuse supplied business answers and approved paperwork where applicable;
  - submit, see plain approval progress, fix the explained problem and resubmit when rejected.
- Server: Twilio's create → link → evaluate → submit sequence, stored in a ledger like the existing Trust Hub
  ledger (`trust-hub-submission-store.ts` pattern).
- Status updates come by webhook, with a daily check as a safety net. This reuses the
  `trust-hub-status-poll-cron.ts` pattern.
- The purchase in Part 2 asks for an approved bundle or address whenever Twilio requires one.

### Part 4 — Readiness per sender and destination
- Remove the fixed `US` and register per sender:
  - **US/Canada local texting US recipients:** the existing 10DLC flow, wired to a "Submit" action;
  - **US/Canada toll-free:** a new Toll-Free Verification flow (Twilio API) that reuses the contractor's already
    collected business answers;
  - **Canada local texting Canadian recipients:** no US 10DLC requirement;
  - **Other routes:** verify applicable sender registration, permitted use cases and destination restrictions
    in addition to any approved purchase bundle.
- Number ownership, paperwork approval and texting readiness are separate facts. Show the next action with
  plain states such as "Business details needed", "Under review", "Action needed" and "Ready to text".
- Platform ISV approval does not replace each contractor's identity or registration.
- Twilio confirms that US and Canadian local numbers require registration for US recipients:
  [registration requirements](https://www.twilio.com/docs/usage/tutorials/how-to-use-your-free-trial-account).

### Part 5 — Sending rules per country
- Default the contractor's intended destination to its home country; this does not bypass readiness checks.
  Contractors request additional destinations inside Uplift and see "Setting up" until verified.
- Uplift operations handles Twilio destination permissions. Twilio does not allow changing SMS Geo Permissions
  through its API; an authorized Uplift administrator uses the Twilio dashboard where necessary and verifies
  the outcome. Account inheritance may already provide the permission; never assume a local switch enables it.
- Check recipient destination, sender suitability, consent, opt-out, recipient-local sending restrictions,
  credit and rate at estimate, enqueue and dispatch. Reuse existing sending guards.
- Picture messages follow both sender and destination support. Where Twilio supports conversion to a link,
  configure it and tell the contractor how the picture will arrive; otherwise explain the restriction.
- Explicitly configure supported opt-out languages and replies. Twilio matches configured keywords; it does
  not translate them. Preserve carrier-specific toll-free opt-out behavior.

### Part 6 — Prices per country
- Reuse the existing credit ledger, destination retail rates and Jafar's rate controls. Twilio's costs inform
  Jafar's published selling rates and margin; provider cost and customer charge remain separate.
- Show the final selling price before sending or committing to a purchase, including applicable recurring
  and setup charges. Preserve the rate used for each charge so later price changes do not rewrite billing.

### Part 7 — Monthly number renewal (approved 2026-10-23)

Today only the first month is charged (`communication_sms_open_number_order`). Twilio bills Uplift every month
for each number it holds, even while an account is suspended, until the number is released.

**How GHL and Twilio do it.** GHL: "All phone numbers are charged monthly"
([LC Phone pricing](https://help.gohighlevel.com/en/support/solutions/articles/48001223556)); usage comes from a
wallet and LC services pause when it drops below zero
([SaaS wallet](https://mycrmsupport.helpjuice.com/saas-wallet-complimentary-credits)); auto recharge needs a saved
card ([Wallet auto recharge](https://help.gohighlevel.com/support/solutions/articles/155000005620)). GHL publishes no
release rule; a third-party guide reports deletion 14 days after a cancel; a released number can be restored within
10 days ([Restore](https://help.gohighlevel.com/support/solutions/articles/48001232056)). Twilio bills the full month
up front from purchase, keeps billing while suspended, stops only on release, and holds a released number 10 days
([balance zero](https://support.twilio.com/hc/en-us/articles/223183248),
[restore](https://support.twilio.com/hc/en-us/articles/223183108)). Uplift has no saved card: top-ups are manual and
confirmed by Jafar.

**Jafar's decisions (2026-10-23):**
1. Renewal is paid from the business's **bought texting balance**, like the first month (promotional credit still
   pays messages only).
2. If the balance cannot cover it, the number enters a **14-day grace** with warnings, then is released.
3. During grace the number is **receive-only**: replies still arrive in the inbox; sending is paused until a top-up
   pays the renewal.

**Rules (proven defaults):**
- Renewal day is the purchase anniversary (Twilio's billing); a number bought on the 31st renews on the last day of
  shorter months. Numbers attached by hand renew one month after attachment.
- The price is the number rate in effect on renewal day, so Jafar's dated price changes apply at each next renewal.
  Each renewal keeps the rate it used.
- Each period is charged once (ledger key `number_renewal:<number>:<period>`).
- A confirmed top-up during grace pays the overdue renewal at once and sending resumes.
- The business owner is warned by email and the notification bell 3 days before renewal when the balance is short,
  when renewal fails, and 3 days before release. Uplift's To do queue shows unpaid numbers.
- Releasing keeps all conversations. Automatic release stays off while live SMS is off.

### Not in this build (later, recorded as deferred)
- GHL's paid identity check (Persona) before +1 numbers.
- WhatsApp for countries without texting numbers.
- Moving an existing number in from another provider (porting).

## Order and design
1. **Current instruction (2026-10-22): update the campaign only; no Pencil design or implementation now.**
   Jafar will start a new session for designing. Pencil designs come first, per the design skill: the Add number
   dialog, the Compliance list and form, per-number readiness, charges, and Uplift's internal setup controls.
   Jafar approves them, then they get built.
2. Part 1 is the server foundation.
3. Parts 2 and 3 run together, because a purchase needs the paperwork.
4. Then Part 4, then Parts 5 and 6.

## Interfaces

Extend existing organization-scoped `/api/*` services for country/number discovery, compliance submissions,
purchases, readiness and destination requests. Validate writes with Zod and keep credentials, the approved
ISV profile ID and provider operations server-side. Reuse sender identities, registrations, SMS mode,
conversations, retail-rate versions and balance records.

## Verification (no money spent)
- Unit tests against fake Twilio replies for every new flow: rejection/resubmission, stock changes, provider
  failures, duplicate/interrupted purchases, destination permission mismatch, unsupported MMS, opt-outs and
  credit reservation/settlement (vitest, like `twilio-trust-hub.spec.ts`).
- Read-only live Twilio calls prove real country data loads: number search and requirements for the US, Canada,
  the UK, Australia, Germany and Brazil. Nothing is bought.
- Follow `docs/screen-check.md` on desktop/mobile and light/dark, covering loading, empty, pending, error and
  ready states. Search shows actual account inventory and selling prices; forms reflect real requirements.
- With the first paying business and Jafar's authorization, prove purchase, required registration, destination
  permission, outbound delivery, inbound reply, opt-out and billing before activation. Repeat applicable checks
  for later destinations. Global selection is not proof of worldwide delivery.

## Platform location (settled 2026-10-22)
Uplift being registered in Bangladesh is not a Twilio limit. The ISV guide requires only an approved Primary Business
Profile of type "ISV Reseller or Partner", with no country rule
([ISV guide](https://www.twilio.com/docs/messaging/compliance/a2p-10dlc/onboarding-isv-api)). The "headquartered outside
the US, Canada, EU, UK, or Australia" line belongs to the Direct guide, which is for businesses registering themselves
([Direct guide](https://www.twilio.com/docs/messaging/compliance/a2p-10dlc/direct-standard-onboarding)). What matters is
the contractor's location: Sole Proprietor (no tax ID) is US/Canada only, so a contractor elsewhere texting US numbers
registers as a Standard brand with its local company number
([Sole Proprietor for ISVs](https://www.twilio.com/docs/messaging/compliance/a2p-10dlc/onboarding-isv-api-sole-prop-new),
[business info](https://www.twilio.com/docs/messaging/compliance/a2p-10dlc/collect-business-info)).

## Approval record

Jafar accepted this plan's direction on 2026-10-22 ("follow GHL totally"; every country Twilio supports; no region blocked in the app — Jafar simply does not sell to Asia).
Each new screen still needs its Pencil design approved before it is built.

**Combined agreement approved 2026-10-22:** after comparing Claude's plan and
[Codex's comparison](global-sms-codex-review-plan.md), Jafar instructed "Implement the plan." The final
agreement retains the GHL journey with the readiness, destination-permission, language and billing corrections
above. His goal: contractors find it easy while Uplift handles provider work behind the scenes.

**Latest scope instruction:** "dont do any pencil design now" and "just udate the campaign". This session
records approval and updates Memory only. No Stage 10 implementation or Pencil work has started. Next delivery
step, when Jafar resumes it, is Pencil design review; approval of this plan does not approve new screens or live
provider spending.
