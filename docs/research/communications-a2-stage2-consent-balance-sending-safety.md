# Communications A2 Stage 2 — consent, balance, and SMS sending safety

Research date: 2026-09-12  
Scope: Current official HighLevel and Twilio documentation for a global ISV serving an initial 100–200 contractor organizations. This note covers consent evidence and current DND state, STOP/START/HELP, quiet hours, Communication Balance, spend controls, sender/use-case separation, pauses, pricing versions, and country limitations. It does not authorize code, schema, provider, or account changes.  
Evidence labels: **Fact** is stated in a cited first-party source. **Inference** is the smallest product or architecture conclusion drawn from those facts. **Departure** is behavior that should intentionally differ from HighLevel and requires Jafar's approval unless already approved in `docs/PRODUCT.md`.

## Executive finding

HighLevel supplies the right visible product shape: channel-specific DND, automatic STOP handling, sender/opt-out text, contact-local workflow windows, per-location messaging limits, a prepaid wallet, agency rebilling, low-balance recharge, and account-level restrictions. Twilio confirms that UCRM, as the ISV, is still responsible for consent proof, country law, tenant isolation, sender/use-case registration, and fraud exposure.

The safe Stage 2 contract is therefore:

1. Keep append-only consent evidence and derive one current SMS eligibility projection; never treat an editable DND toggle as the evidence itself.
2. Let Twilio enforce provider STOP/START/HELP for each Messaging Service, mirror every event locally, and never send a second automatic confirmation.
3. Evaluate every normal outbound message at dispatch time against purpose, sender, country, quiet hours, consent, registration, organization mode, pauses, spend cap, and reserved balance.
4. Keep UCRM's per-organization prepaid Communication Balance separate from Twilio's shared parent balance. Reserve retail credit before queueing and settle it from the final billed result.
5. Use one Twilio subaccount per contractor and separate Messaging Services by approved use case. Keep the parent account as a control/billing shell with no customer traffic.
6. Enable destinations country by country only after sender capability, registration, opt-out path, pricing, legal rules, and live two-way behavior are verified.

This preserves HighLevel's contractor-facing mental model while adding the provider and tenant safeguards HighLevel does not expose.

## 1. Consent evidence and the current DND projection

### Provider and HighLevel facts

- **Fact:** Twilio requires prior consent before sending, ties consent to each recipient, sender, and message subject, requires proof of the date and collection method, and makes the ISV responsible for requiring its contractor customers to obtain downstream-user consent. A recipient's inbound message can itself be consent and proof for replying within that exchange. ([Twilio Messaging Policy](https://www.twilio.com/en-us/legal/messaging-policy))
- **Fact:** Twilio's Consent Management API stores current opt-in/opt-out/re-opt-in state across SMS, MMS, and RCS, but it is a synchronization/blocking API, not a substitute for the ISV's retained proof. The API is globally available but may require enablement and has its own limits. ([Twilio Consent Management API](https://www.twilio.com/docs/messaging/features/consent-api))
- **Fact:** HighLevel exposes global and channel-specific DND. It records whether a workflow, user, or contact changed DND. HighLevel also says SMS DND can be activated by STOP or by delivery errors such as unreachable/invalid destinations; a permanent SMS DND requires START or proof supplied to support, while a temporary DND may be manually changed. ([HighLevel DND](https://help.gohighlevel.com/support/solutions/articles/48001214849))

### Required UCRM shape

**Inference:** Store consent as immutable organization-scoped events, then maintain a replaceable current projection for fast send-time checks.

Minimum evidence per event:

- organization, contact, normalized destination, channel, contractor Brand/sender, and message subject/purpose;
- grant, revoke, re-opt-in, manual hold, release, or provider signal;
- disclosure/version shown, collection method and source, occurred time and received time;
- actor or customer origin, source IP/form/provider reference where available, and a safe evidence pointer;
- previous and resulting projected state.

The current projection should separately expose:

- legal consent: `unknown`, `opted_in`, or `opted_out`;
- contractor preference/DND: allowed or blocked;
- deliverability suppression: valid, temporarily unreachable, invalid/reassigned, or unknown;
- the sender/use-case scope, latest evidence event, and whether only a customer-originated re-opt-in can clear the block.

Every manual, Automation, retry, and delayed send reads this projection at dispatch time. Editing a contact never deletes or rewrites the evidence.

**Departure 1 — do not copy HighLevel's single SMS DND meaning literally.** A carrier error is not proof that a person revoked consent. UCRM should show one actionable “SMS unavailable” result, but retain distinct legal opt-out, contractor hold, and technical deliverability reasons underneath. Only STOP, another valid revocation, or equivalent legal evidence creates the locked legal hard stop. This is a necessary audit and recovery improvement over HighLevel's documented error-to-DND behavior.

**Departure 2 — workflows and ordinary users cannot clear a legal STOP.** HighLevel exposes workflow DND actions, but its own permanent-DND guidance requires START or reviewed proof. UCRM may let authorized staff set or clear an ordinary business hold; a legal opt-out clears only from a valid customer re-opt-in or a narrowly controlled proof-review action with immutable owner history.

## 2. STOP, START, HELP, and sender identification

- **Fact:** Twilio handles standard English STOP-family keywords on long codes by default. Advanced Opt-Out is configured per Messaging Service and adds case-insensitive exact-message classification, custom responses, language and country overrides, and an inbound `OptOutType` of `STOP`, `START`, or `HELP`. Twilio has already sent the configured reply when `OptOutType` is present, so the application should not send another one. ([Twilio Advanced Opt-Out](https://www.twilio.com/docs/messaging/tutorials/advanced-opt-out), [Twilio `OptOutType` behavior](https://help.twilio.com/articles/31560110671259))
- **Fact:** STOP blocks later sends with error `21610`. START/UNSTOP removes the provider block; a re-opt-in applied through the Consent Management API must clear both the Messaging Service-level and individual sender-level records. For US toll-free senders, only START and UNSTOP fully reverse the carrier block; YES is insufficient. ([Twilio Advanced Opt-Out](https://www.twilio.com/docs/messaging/tutorials/advanced-opt-out), [Twilio Consent Management API](https://www.twilio.com/docs/messaging/features/consent-api))
- **Fact:** HELP does not change opt-out state. Twilio recommends that help text identify the owner and available actions. ([Twilio Advanced Opt-Out](https://www.twilio.com/docs/messaging/tutorials/advanced-opt-out))
- **Fact:** Twilio requires the initial message to identify the party that obtained consent and include a one-step opt-out instruction. HighLevel follows this by appending sender identity and opt-out language to the first outbound message and can repeat it every 1–60 days; new HighLevel subaccounts default the periodic behavior on with 30 days. ([Twilio Messaging Policy](https://www.twilio.com/en-us/legal/messaging-policy), [HighLevel periodic compliance text](https://help.gohighlevel.com/support/solutions/articles/155000006771-set-up-automatic-opt-out-and-sender-info-updates-in-messaging-compliance))

**Inference:** Enable and version Advanced Opt-Out configuration for every two-way Messaging Service before readiness. Store each `OptOutType` webhook as consent evidence and update the current projection in the same idempotent processing path. The customer-facing timeline should show a system event, not a duplicate UCRM-authored SMS.

The configuration must be sender/use-case/country aware. Registration samples, short-code keyword promises, toll-free behavior, localized keywords, and confirmation text must agree. UCRM should use the HighLevel pattern of first-message sender/opt-out text plus a platform-controlled periodic reminder; contractors may customize truthful business identity within approved rules but cannot remove the required mechanism.

One-way alphanumeric sender IDs cannot receive STOP, START, HELP, or conversation replies. Twilio requires explicit opt-in and an alternative opt-out route for them. They may support approved notifications in eligible countries, but they must never be presented as Two-way SMS in Conversations. ([Twilio Alphanumeric Sender IDs](https://www.twilio.com/docs/numbers-and-senders/alphanumeric-senders))

## 3. Quiet hours and delayed sends

- **Fact:** HighLevel workflows can use either the account timezone or the contact timezone and a workflow Time Window. A communication action outside the window pauses until the next window; if a contact timezone is missing, HighLevel falls back to the account timezone. The window is workflow-wide, not a universal manual-send gate. ([HighLevel workflow settings](https://help.gohighlevel.com/support/solutions/articles/48001239875))
- **Fact:** Twilio Compliance Toolkit's Quiet Hours protection covers US outbound SMS only. It uses recipient-local time, inferred from area code unless a known ZIP code is supplied, and by default reschedules non-essential messages sent from 9 PM through 8 AM. Explicit `messageIntent` can mark supported use cases essential or non-essential and overrides Twilio's model. ([Twilio Compliance Toolkit](https://www.twilio.com/docs/messaging/features/compliance-toolkit))
- **Fact:** Twilio says each country has its own regulatory framework, potentially varying by sender and use case; the customer remains responsible for it. ([Twilio SMS Geo Permissions](https://www.twilio.com/docs/messaging/guides/sms-geo-permissions), [Twilio country SMS guidelines](https://www.twilio.com/en-us/guidelines/sms))

**Inference:** UCRM needs one send-time quiet-hours policy for normal outbound SMS across manual and automated sources, not only a workflow authoring window. Resolve the rule from destination country, local subdivision where required, message purpose, and recipient-local time. Preserve the time-zone source and confidence; a verified contact timezone/ZIP outranks number inference, and a safe organization fallback applies when local time is unknown.

Outside the permitted window, schedule rather than provider-submit. At release time, recheck the work item, expiry, sender readiness, consent, balance, cap, and pauses so stale reminders and newly opted-out contacts do not send. Recent customer-support replies and legally permitted essential notices can use an explicit purpose exception; contractors cannot label arbitrary marketing as essential.

**Departure 3 — HighLevel's configurable workflow window is not the legal boundary.** Keep that familiar authoring control, but enforce a non-bypassable jurisdiction/purpose guard beneath it. Twilio's US toolkit is defense in depth, not the global source of truth. Launch-country legal review remains required.

## 4. Communication Balance, rebilling, and zero balance

### What HighLevel and Twilio actually bill

- **Fact:** HighLevel uses a prepaid Agency Wallet for usage-based services. HighLevel always charges the agency first; optional rebilling then charges a prepaid subaccount wallet at cost or with agency markup. Wallets auto-recharge below a threshold, and negative balance temporarily halts LC services until payment succeeds. ([HighLevel wallets and rebilling](https://help.gohighlevel.com/support/solutions/articles/155000002095), [HighLevel wallet auto-recharge](https://help.gohighlevel.com/support/solutions/articles/155000005620/))
- **Fact:** HighLevel bills SMS by segments and may charge for an attempted message once it has reached the provider even if delivery later fails. Its public estimator says final cost is known only after sending and prices can change. ([HighLevel SMS cost calculation](https://help.gohighlevel.com/support/solutions/articles/48001203458), [HighLevel Phone pricing](https://help.gohighlevel.com/support/solutions/articles/48001223556-lc-phone-pricing-structure))
- **Fact:** Twilio subaccounts do not have independently funded balances: all their usage is billed to the parent account. If the parent balance reaches zero, the parent and subaccounts are suspended from all Twilio usage, while recurring charges such as numbers and campaigns continue. ([Twilio subaccounts](https://www.twilio.com/docs/iam/api/subaccounts), [Twilio zero balance](https://help.twilio.com/articles/223183248))

### Required ledger and reservation behavior

**Inference:** UCRM's Communication Balance must remain an application-owned retail ledger, not a copy of the Twilio parent balance and not an editable number.

For every normal outbound attempt:

1. calculate an honest maximum/estimated segment cost using one published retail-rate version;
2. atomically reserve organization credit before creating the durable send intent;
3. settle the retail charge when the provider's billed result is known;
4. release the reservation only when no billable provider attempt occurred, or append a reasoned adjustment;
5. keep provider cost and retail charge as separate immutable entries.

Promotional credit and purchased credit stay separate under the already approved order. Provider-billed inbound SMS, STOP/START/HELP, and required callbacks continue at zero organization balance and become Outstanding Communication Usage; later purchased credit settles debt before becoming spendable. A later delivery failure does not automatically refund a provider-billed attempt.

**Departure 4 — no HighLevel-style automatic card recharge or direct rebilling in this release.** The approved UCRM model uses verified offsite Top-up Requests and immutable Purchased Credit. That is a commercial departure from HighLevel, not a Twilio limitation. It avoids silently charging contractor cards but means low-balance warnings and pre-send reservations must be strict.

**Departure 5 — never suspend a Twilio subaccount merely because its UCRM balance is low.** Twilio suspension blocks inbound SMS as well as outbound and still incurs recurring number costs. Routine balance, package, or organization pauses must remain UCRM outbound gates so inbound replies and mandatory consent events continue.

Protect the separate Twilio parent balance with auto-recharge and an owner-visible reserve floor. If that shared reserve is threatened, stop new normal outbound platform-wide before Twilio reaches zero; keep callback/reconciliation workers alive and raise an urgent owner incident. This is essential because one depleted parent balance can disable every contractor.

For the contractor-facing low-balance state, follow the already approved `docs/PRODUCT.md` behavior: warn at the global threshold, when recent use predicts fewer than seven days remaining, or when the next known number/registration renewal is not covered. At zero spendable balance, show the specific blocked amount and top-up path; do not pretend the SMS connection itself is broken. Protect an underfunded active number for the approved 30-day recovery window while normal outbound is paused, because releasing it is a separate destructive decision.

## 5. Spend limits, rate limits, and fraud controls

- **Fact:** HighLevel provides per-location daily or monthly message/segment limits and an eight-level messaging ramp. Limits cover one-to-one and automated SMS; reaching a ramp level can pause outbound SMS for 24 hours. HighLevel states that provider/carrier limits still apply, and failed workflow SMS is not automatically retried after a restriction. ([HighLevel messaging limits](https://help.gohighlevel.com/support/solutions/articles/155000006385), [HighLevel messaging ramp](https://help.gohighlevel.com/support/solutions/articles/155000005572-messaging-ramp-progress-card), [HighLevel messaging policy](https://help.gohighlevel.com/support/solutions/articles/48001213941))
- **Fact:** Twilio Usage Triggers can alert on a subaccount's daily/monthly/yearly count, usage, or price, but evaluations are delayed and occur about once per minute. Twilio documents them as a circuit-breaker input, not an atomic pre-send limit. ([Twilio Usage Triggers](https://www.twilio.com/docs/usage/api/usage-trigger), [Twilio fraud circuit breaker](https://help.twilio.com/articles/223132387-Protect-your-Twilio-project-from-Fraud-with-Usage-Triggers))
- **Fact:** Twilio queues above sender throughput, can fail an overfull queue with `30001`, and permits a message validity period up to 10 hours. SMS Pumping Protection is configured per account/subaccount, not inherited from the parent. Twilio also recommends destination-country restrictions and application rate limits. ([Twilio queue overflow](https://www.twilio.com/docs/api/errors/30001), [Twilio Messaging Services](https://www.twilio.com/docs/messaging/services), [Twilio SMS Pumping Protection](https://www.twilio.com/docs/messaging/features/sms-pumping-protection-programmable-messaging), [Twilio fraud prevention](https://www.twilio.com/docs/messaging/guides/preventing-messaging-fraud))

**Inference:** Enforce caps synchronously in UCRM, in the same transaction as the balance reservation and send intent. Keep independent, reasoned ceilings for per-message estimated spend, organization daily spend, organization daily segments, destination-country bursts, sender/service throughput, and the global protected reserve. Provider Usage Triggers and alerts are backup detection, never the sole limit.

Use Twilio subaccount suspension only as a reversible emergency fraud containment action with an impact warning, owner reason, immutable audit, and deliberate resume. It is too broad for normal commercial enforcement because it also disables inbound.

Do not replay all messages after a pause or rate restriction. Each blocked/skipped/expired message remains visible with its exact reason. A deliberate retry creates or reuses the correct logical send key, reruns every current safety gate, and avoids duplicate customer contact and charges.

## 6. Sender and use-case separation

- **Fact:** Twilio's preferred ISV architecture is one subaccount per customer. For US A2P 10DLC, each customer Brand and each Campaign/use case belongs in that customer's subaccount, and each use case maps to its own Messaging Service. Twilio says the isolation simplifies analytics and limits one noncompliant customer's impact. ([Twilio ISV A2P onboarding](https://www.twilio.com/docs/messaging/compliance/a2p-10dlc/onboarding-isv))
- **Fact:** Twilio's broader onboarding guide recommends that the parent carry no traffic, that all sending occur in customer subaccounts, and that use cases be separated by Messaging Service as much as practical for compliance, reporting, throughput, and number pools. ([Twilio account architecture](https://www.twilio.com/docs/messaging/onboarding/build-your-account))

**Inference:** Keep the approved Stage 1 boundary: one contractor subaccount; one connection record; separate sender identities; and one Messaging Service per approved use case. Manual support/conversation traffic and operational notifications may share only where the selected country/sender registration truthfully permits the combined use case. Marketing remains a later, separately registered service and lane.

An Automation step may choose SMS generally, but at dispatch it must resolve to an approved service whose registered use case matches the actual message purpose. “General SMS” in the workflow authoring UI is not permission to route every message through one provider campaign.

## 7. Platform and organization pause semantics

HighLevel separates contact DND, outbound messaging restrictions, and full subaccount pause. Its SMS restriction leaves inbound conversations available; SMS workflow actions reached during the restriction can fail and are not automatically retried. ([HighLevel messaging policy](https://help.gohighlevel.com/support/solutions/articles/48001213941), [HighLevel pause/resume](https://help.gohighlevel.com/support/solutions/articles/48001230403/))

**Inference:** Use reason-coded, independently auditable gates:

- global normal-outbound pause;
- protected-provider-balance pause;
- organization normal-outbound pause;
- organization SMS Mode/package maximum;
- sender/service/registration/country readiness;
- contact consent/DND/deliverability;
- quiet-hours scheduling;
- balance reservation and spend/rate limits;
- provider/fraud health.

All normal outbound sources use the same gate, including staff, Automations, retries, and future campaigns. Pauses preserve history, inbound messages, STOP/START/HELP, delivery/status callbacks, provider registration events, billing reconciliation, and owner recovery operations.

Resume does not release a stale backlog. Each queued or scheduled message is re-evaluated; obsolete appointment reminders, completed-work follow-ups, expired intents, and newly blocked recipients are cancelled or skipped with an explanation.

## 8. Retail-rate versioning and settlement

- **Fact:** Twilio's Pricing API returns current, account-specific inbound and outbound country/carrier/number-type rates. Its response does not provide a historical price version or effective date. A Message resource's final `price` is populated only after send/receive and may not be immediately available; Twilio bills each SMS segment. ([Twilio Messaging Pricing API](https://www.twilio.com/docs/messaging/api/pricing), [Twilio Message resource](https://www.twilio.com/docs/messaging/api/message-resource))
- **Fact:** Twilio Usage Records aggregate price, count, and usage by category and subaccount and are suitable for reconciliation and usage-based billing. ([Twilio Usage Records](https://www.twilio.com/docs/usage/api/usage-record))
- **Fact:** Encoding affects segment count: concatenated GSM-7 and UCS-2 messages carry fewer characters per segment, and Twilio charges per segment. International capabilities and costs vary by country. ([Twilio international SMS guide](https://www.twilio.com/docs/messaging/guides/sending-international-sms-guide))

**Inference:** Every published UCRM retail rate needs an immutable version and effective interval keyed by destination country, direction, channel, sender type, encoding/segment unit, provider platform fee, carrier fee policy, and any recurring number/registration fee. A send reservation stores the exact rate version and estimated segments; settlement stores actual segments, provider charge/currency, retail charge, and any difference. New rates affect new reservations only and never rewrite history.

The composer may show an estimate and segment warning, especially for emoji/Unicode, but must not call it a guaranteed final price. Reconcile message-level provider prices as they arrive and use Usage Records to detect missing or aggregate discrepancies.

**Departure 6 — do not copy HighLevel's current-price-plus-markup calculation as historical truth.** HighLevel's live price pages and wallet UX are useful display references, but UCRM must make the contractor's applied retail rate reproducible later. Hidden or retroactive recalculation would break ledger auditability.

## 9. Country-specific and global limitations

- **Fact:** Twilio instructs senders to review each target country's legal rules, available sender types, two-way support, concatenation, Unicode, registration, and pricing before sending. ([Twilio international SMS guide](https://www.twilio.com/docs/messaging/guides/sending-international-sms-guide), [Twilio country SMS guidelines](https://www.twilio.com/en-us/guidelines/sms))
- **Fact:** SMS Geo Permissions default new accounts to the signup home country. Parent settings are inherited by subaccounts unless inheritance is disabled; changes are Console-only, immediate, and auditable. Twilio recommends disabling countries not actually used. ([Twilio SMS Geo Permissions](https://www.twilio.com/docs/messaging/guides/sms-geo-permissions))
- **Fact:** Twilio Compliance Toolkit Quiet Hours is US-only. Alphanumeric sender IDs are unsupported in the US/Canada and are one-way even where allowed. SMS Pumping Protection is separately enabled/evaluated per subaccount. ([Twilio Compliance Toolkit](https://www.twilio.com/docs/messaging/features/compliance-toolkit), [Twilio Alphanumeric Sender IDs](https://www.twilio.com/docs/numbers-and-senders/alphanumeric-senders), [Twilio SMS Pumping Protection](https://www.twilio.com/docs/messaging/features/sms-pumping-protection-programmable-messaging))

**Inference:** “Global” means a global-capable model with a controlled enabled-country register, not every country switched on at launch. Each enabled combination must record:

- origin and destination country;
- sender type, two-way capability, and provisioning/registration state;
- allowed use cases and content constraints;
- consent/opt-out mechanism and supported languages;
- quiet-hours/legal-policy version and timezone source;
- current provider/retail rate versions and spend caps;
- geo-permission and pumping-protection readiness;
- successful live outbound, inbound, STOP, START, HELP, failure, and billing proof.

Where Twilio exposes no API for a readiness setting, keep an owner-confirmed desired/observed record and fail closed until the provider Console state is verified. Do not hardcode a permanent US/Canada matrix; refresh country facts before each enablement and periodically afterward.

## Material departures from HighLevel to approve or acknowledge

1. **Separate legal consent, business DND, and delivery suppression.** HighLevel can place provider delivery errors into SMS DND; UCRM should not mislabel a technical failure as revoked consent.
2. **No workflow/user override of legal STOP.** Re-opt-in needs a customer-originated START or reviewed proof, not an ordinary DND toggle.
3. **Non-bypassable global quiet-hours policy.** HighLevel's workflow window remains a useful authoring feature, but it cannot protect manual sends or cover non-US law by itself.
4. **No automatic contractor-card recharge at launch.** UCRM keeps the already approved offsite Top-up Request and immutable credit ledger instead of copying HighLevel rebilling.
5. **No routine Twilio subaccount suspension for low UCRM balance or package pause.** App-level outbound gates preserve inbound and consent traffic.
6. **Versioned retail rates and reservations.** UCRM keeps the exact applied rate instead of reconstructing historical charges from a current provider/markup table.
7. **Country-by-country activation.** UCRM presents a global-capable product, but enables only proven country/sender/use-case combinations rather than implying that Twilio's global reach equals universal two-way/compliant readiness.

Departures 4, 5, 6, and the country-by-country principle already appear in `docs/PRODUCT.md` §11. Departures 1–3 sharpen the consent and quiet-hours boundary and should be explicitly accepted before Stage 2 is promoted into the durable contract or implementation plan.

## Stage 2 completion checks for the later implementation plan

- STOP from every enabled two-way sender blocks manual, Automation, retry, and scheduled outbound before provider submission; one provider confirmation appears and one local evidence event is stored.
- START/UNSTOP restores only the correct sender/service scope after both provider and local state agree; HELP never changes consent.
- A legal opt-out cannot be cleared by a normal user or workflow; an ordinary business hold can be distinguished and audited.
- Quiet-hours tests cover contact timezone, missing timezone fallback, scheduling, recheck on release, essential-purpose exception, and every launch country.
- Simultaneous sends cannot overspend one organization balance or daily cap; retries cannot double-reserve or double-charge.
- Zero organization balance still accepts inbound and consent traffic and records provider-billed debt; protected parent reserve prevents Twilio-wide suspension.
- Platform and organization pauses stop all normal outbound sources while callbacks, reconciliation, registration events, and inbound continue.
- Rate changes never alter old ledger entries; Unicode/segment estimates reconcile to final provider charges.
- Each launch-country sender proves registration, outbound, inbound where promised, STOP/START/HELP or the approved alternative opt-out, failure visibility, fraud controls, and billing in a live test.

## Research limits

This is product/provider research, not legal advice. Twilio explicitly places country-law responsibility on the customer, so qualified legal review remains a launch gate for each enabled country and message purpose. HighLevel's public support pages describe visible behavior but not its internal ledger consistency, consent schema, or exact provider-account controls; those internal details were not inferred.
