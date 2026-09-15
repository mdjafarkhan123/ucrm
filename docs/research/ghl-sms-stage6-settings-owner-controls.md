# HighLevel SMS settings and owner controls — Stage 6 research

Research date: 2026-09-12  
Scope: Current first-party HighLevel Help Center and HighLevel changelog evidence for contractor-facing
phone/SMS readiness, number and registration states, messaging analytics, wallet behavior, and
agency/platform-owner controls. This note records competitor behavior only. It does not propose UCRM features,
technical design, schema, APIs, or implementation.  
Evidence boundary: HighLevel's native **LC Phone** behavior is the main subject. Where HighLevel mentions an
agency-owned Twilio connection, that is identified separately. No third-party descriptions were used.

## Executive finding

HighLevel's smallest proven product shape is not one large phone-settings screen. It is a small set of distinct
surfaces:

1. a phone-number list that shows number capability and registration readiness;
2. a Trust Center for submitting registration and correcting rejected submissions;
3. messaging analytics for delivery health, opt-outs, failure reasons, and message-level investigation;
4. a separate billing/wallet view for balance, spend, transactions, and recharge;
5. agency controls for defaults, rebilling, usage limits, wallet alerts, and location access; and
6. read-only restriction history plus execution/message logs for recovery.

HighLevel also keeps several states meaningfully separate: **approved registration is not the same as a linked,
ready number; messaging restriction is not the same as low balance; and a paused sub-account is not the same as
an SMS-only pause.** Its own recovery guidance says failed workflow SMS is not automatically replayed when a
restriction ends.

The commercial model is the major mismatch with UCRM. HighLevel automatically funds wallets from saved cards
and can automatically rebill a sub-account. UCRM has already approved offsite Top-up Requests that create no
credit until the Platform Owner confirms payment. HighLevel's native LC Phone model also hides the upstream
provider relationship, while UCRM has already approved one platform-owned Twilio parent account with one
isolated Twilio subaccount per contractor.

## 1. Contractor-facing phone and registration readiness

### Number setup is separate from messaging approval

HighLevel exposes available-number type and capabilities such as Voice, SMS, and MMS during number selection.
After purchase, the number appears under **Settings > Phone System > Phone Numbers**, but HighLevel does not
treat purchase alone as messaging readiness. The number is configured and tested, then the user completes the
registration required for that number type: US local 10DLC uses A2P 10DLC; US/Canada toll-free messaging uses
Toll-Free Verification. [HighLevel phone-number purchase and setup](https://help.gohighlevel.com/support/solutions/articles/155000003226)

For US local numbers, **Settings > Phone System > Trust Center** contains the Brand and Campaign registration
flow. HighLevel describes Brand as the business identity and Campaign as the messaging purpose and consent
flow. HighLevel supplies the workflow, but carriers and registration partners make the final approval or
rejection decision. [HighLevel A2P Brand and Campaign registration](https://help.gohighlevel.com/support/solutions/articles/155000002380)

HighLevel documents these campaign outcomes clearly enough for the visible journey:

- a new submission is **Pending** while reviewed;
- a **Rejected** campaign exposes every rejection reason through **View required fixes**;
- an approved campaign still does not prove that SMS works; the sending number must be linked to the approved
  campaign and show the green **A2P Verified** label in Phone Numbers; and
- a registration or deregistration may still be propagating, surfaced as error `30035`; HighLevel advises
  checking Trust Center and number status and allowing the propagation window before escalating.

[HighLevel A2P Campaign registration guide](https://help.gohighlevel.com/support/solutions/articles/155000004539-campaign-registration-step-by-step-guide-and-faqs),
[HighLevel error and warning dictionary](https://help.gohighlevel.com/support/solutions/articles/155000005526)

Rejected A2P submissions show an error code, category, meaning, and correction. Some corrections can be
resubmitted; some locked fields require a new Campaign. Support can explain the problem and assist with an
eligible resubmission or appeal, but cannot overrule the carrier decision.
[HighLevel A2P rejection fixes](https://help.gohighlevel.com/support/solutions/articles/155000007572-understanding-a2p-campaign-rejection-reasons-required-fixes)

Toll-free numbers have a more explicit operational status model:

| HighLevel status | US/Canada SMS/MMS | Visible next meaning |
| --- | --- | --- |
| **Restricted (Unverified)** | Blocked | Verification has not been submitted or approved. |
| **Pending Verification** | Blocked | Wait for review; do not test production messaging. |
| **Verified (Approved)** | Allowed | Messaging may proceed subject to all other platform, carrier, consent, and content rules. |
| **Rejected** | Blocked | Review the reason, correct, resubmit, or appeal when eligible. |

Voice remains available regardless of this toll-free messaging-verification status, and each toll-free number
has its own submission and status. [HighLevel Toll-Free Verification guide](https://help.gohighlevel.com/support/solutions/articles/48001222300-toll-free-verification-guide-for-lc-phone-us-canada-)

### Documentation limit

HighLevel's current readable A2P documentation does not publish one complete canonical enum for every Brand,
Campaign, number-linking, and carrier-propagation intermediate state. The confirmed product concepts are
submission/review, rejection with required fixes, approval, number association/verification, and propagation.
A universal GHL registration state machine should not be inferred beyond those facts.

## 2. Contractor-facing messaging health and diagnostics

**Settings > Phone System > Messaging > Messaging Analytics** is HighLevel's operational health surface. It
shows Sent, Delivered, Failed, Received, and Opt-Out Rate; comparison with the preceding period; failure-rate
and opt-out trends; failure-reason grouping; and clickable message logs with contact, phone number, status,
activity date, and error code. The default reporting range is 30 days and the maximum is 90 days. Outbound
source filters cover All, Campaign, Workflow, and Bulk Request.
[HighLevel Messaging Analytics](https://help.gohighlevel.com/support/solutions/articles/155000002625)

HighLevel deliberately separates summary health from individual diagnosis. Failed-message details and error
codes explain why a number or message failed; the dashboard's monitoring markers are not themselves the rules
that impose a restriction. That matters because the analytics page uses investigation markers while the
Restriction History page separately documents enforced restriction thresholds.

When delivery fails, HighLevel exposes evidence in several existing work surfaces rather than only in a phone
admin page:

- failed messages in Conversations;
- the contact activity/communication timeline;
- Workflow Execution Logs for automated sends; and
- the provider log/error dictionary for the provider-level reason.

HighLevel's troubleshooting guide frames failures in three layers: the HighLevel platform, the phone provider,
and the destination carrier. It tells support users to retain the sending number, destination number, timestamp,
and exact error code when escalating. [HighLevel SMS delivery troubleshooting](https://help.gohighlevel.com/support/solutions/articles/48000981696)

## 3. Messaging restrictions and recovery

HighLevel distinguishes three restriction scopes:

| Restriction | Scope and visible effect |
| --- | --- |
| Ramp or sending limit | Further outbound SMS/MMS attempts can fail after the location reaches its current limit. |
| Compliance restriction | Outbound SMS can fail because messaging-health or policy thresholds were exceeded. |
| Contact SMS DND | SMS is blocked for that contact rather than the whole location. |

Inbound conversations continue during an outbound restriction. A workflow that reaches Send SMS during the
restriction can continue through its other logic while that SMS fails; HighLevel says the failed SMS is **not
automatically retried** when service returns. Its documented recovery sequence is to identify the restriction,
correct the cause, inspect affected message and workflow logs, and selectively resend or re-enrol only where
appropriate. [HighLevel LC Phone Messaging Policy](https://help.gohighlevel.com/support/solutions/articles/48001213941)

The contractor can inspect **Settings > Phone System > Messaging > Restriction History**. This is a read-only,
UTC log with date filters and records of warning or temporary restriction, reason, time, and the measured count
or percentage. HighLevel currently documents a 24-hour lockout at a 3% opt-out rate or 10% delivery-error rate.
[HighLevel SMS Restriction History](https://help.gohighlevel.com/support/solutions/articles/155000003568-sms-restriction-history)

HighLevel also exposes an eight-level Messaging Ramp card in Phone System. It shows the current daily capacity,
progress, and next step. Hitting a level's limit temporarily disables outbound SMS for 24 hours while inbound
messages continue. HighLevel's later general limit control can be expressed in messages or segments, and a
reached limit produces a banner on the Phone Numbers page plus email notification.
[HighLevel Messaging Ramp](https://help.gohighlevel.com/support/solutions/articles/155000005572-messaging-ramp-progress-card),
[HighLevel messaging limits](https://help.gohighlevel.com/support/solutions/articles/155000006385)

### Documented threshold tension

Messaging Analytics describes failure and opt-out markers as monitoring indicators and explicitly says they do
not replace warning, limit, or restriction rules. Restriction History separately describes 10% delivery error
and 3% opt-out as lockout thresholds. These are different meanings, not one reusable “health status.” Current
policy values should be rechecked before any launch claim because HighLevel can change them.

## 4. Usage, wallet, top-ups, and low balance

HighLevel keeps message performance separate from money. Agency billing exposes a prepaid **Wallet &
Transactions** area with current balance, month-over-month category spend, a unified transaction log across
locations, CSV export, and drill-down from a transaction ID to the individual message or charge. HighLevel notes
that spend-summary data can lag by up to 24 hours.
[HighLevel LC Communications spending](https://help.gohighlevel.com/support/solutions/articles/48001225291-how-to-analyze-an-agency-s-spending-on-lc-communications)

Its Agency Wallet Summary adds total spend, month-over-month change, top spender, biggest spike, a searchable
sub-account breakdown, and a per-product drawer.
[HighLevel Agency Wallet Summary](https://help.gohighlevel.com/support/solutions/articles/155000007776-agency-billing-wallets-transactions-summary)

HighLevel's wallet is card-funded and automatic:

- auto-recharge adds a configured amount when balance crosses a configured threshold;
- agency auto-recharge cannot be disabled;
- Smart Adjustment/Auto-update may raise the recharge tier when the same amount triggers more than three times
  in seven days, although this adjustment can be disabled; and
- a failed agency-card charge notifies agency admins, while a negative agency balance can interrupt
  communications across all clients.

[HighLevel Wallet Auto Recharge](https://help.gohighlevel.com/support/solutions/articles/155000005620/),
[HighLevel LC Communications spending](https://help.gohighlevel.com/support/solutions/articles/48001225291-how-to-analyze-an-agency-s-spending-on-lc-communications)

For a rebilled SaaS location, HighLevel has also documented a location-dashboard low-balance warning with a
**Resolve** path to Company Billing. If recharge fails and the location reaches zero, outbound communications
stop. The location can add credits or repair its payment method.
[HighLevel low-balance warning changelog](https://ideas.gohighlevel.com/changelog/low-balance-warning-for-saas-clients-sub-account-users)

## 5. Agency/platform-owner controls visible in HighLevel

### Phone defaults and limits

HighLevel's agency **Phone Integration > Account Creation** settings can automatically attach new sub-accounts
to LC Phone, allow sub-account users to submit A2P even when rebilling is disabled, enable Number Intelligence
by default, and set the initial messaging-limit model. The default applies to newly created sub-accounts;
location-specific limit controls can override it where the account is eligible.
[HighLevel default phone preferences](https://help.gohighlevel.com/support/solutions/articles/155000004593)

Agency Owners/Admins can set a general daily/monthly message or segment limit and, when eligible, adjust one
sub-account's limit. Going beyond the location's maximum requires HighLevel support review. HighLevel explicitly
warns that a platform setting does not override provider/carrier filtering or restrictions.
[HighLevel messaging limits](https://help.gohighlevel.com/support/solutions/articles/155000006385)

### Pricing and rebilling

HighLevel always deducts a sub-account's LC service usage from the Agency Wallet first. With no rebilling, the
agency absorbs the cost. With rebilling, the agency's connected Stripe account funds a prepaid sub-account
wallet from the client's valid card and recovers either HighLevel cost or an agency-marked-up retail price.
[HighLevel rebilling, reselling, and wallets](https://help.gohighlevel.com/support/solutions/articles/155000002095)

HighLevel currently ties rebilling and markup availability to specific HighLevel subscription tiers. Those plan
names and prices are mutable competitor packaging, not a durable behavior rule. HighLevel also documents that
some carrier and A2P charges pass through without markup even when other communication usage is marked up.
[HighLevel wallets, charges, and rebilling](https://help.gohighlevel.com/support/solutions/articles/155000001156),
[HighLevel LC Communications spending](https://help.gohighlevel.com/support/solutions/articles/48001225291-how-to-analyze-an-agency-s-spending-on-lc-communications)

Agency billing notifications can watch sub-account wallet usage over a selected period and email the owner plus
optional recipients after a threshold is exceeded, limited to one notice for that sub-account per day.
[HighLevel wallet notifications](https://help.gohighlevel.com/support/solutions/articles/155000002095)

### Location pause is not an SMS pause

HighLevel's **Pause Sub-Account** is an agency/SaaS access and subscription control. It can be triggered by a
failed SaaS subscription or applied manually by an Agency Admin. Client access is blocked, all workflows become
drafts, agency admins retain access, and a SaaS payment recovery can automatically resume the account. A regular
sub-account requires an agency-admin resume. HighLevel's own FAQ says other functions continue, making this an
especially poor proxy for a precise outbound-SMS restriction.
[HighLevel pause/resume sub-accounts](https://help.gohighlevel.com/support/solutions/articles/48001230403/)

## 6. Explicit gaps and conflicts with approved UCRM decisions

This table records fit only; it does not make a new product decision.

| HighLevel evidence | Approved UCRM position | Gap or conflict |
| --- | --- | --- |
| Agency and rebilled sub-account wallets recharge automatically from saved cards. | A contractor submits an offsite Top-up Request; it creates no spendable credit until the Platform Owner verifies receipt and confirms it. | **Direct commercial conflict.** HighLevel's recharge and “fix card to unlock” flow cannot be copied as UCRM's top-up truth. |
| HighLevel can charge the client wallet automatically at cost or markup after charging the Agency Wallet. | UCRM derives contractor balance from an immutable application ledger; Purchased and Promotional Credit remain distinct; provider cost and retail charge stay separate. | **Model conflict.** HighLevel proves the usefulness of balance, usage, pricing, and owner margin views, but not UCRM's approved confirmation and ledger behavior. |
| LC Phone is the native provider and abstracts upstream telephony; HighLevel also supports separate BYOT Twilio paths. | The Platform Owner owns the Twilio parent account; each contractor has an isolated Twilio subaccount under it. | **Provider-ownership gap.** GHL's screens do not prove the owner diagnostics, parent-reserve controls, or tenant/provider reconciliation UCRM needs. |
| Negative Agency Wallet can interrupt communications across all client locations. | UCRM protects the private Twilio parent balance with an owner-visible reserve floor and stops normal outbound before provider-wide depletion, while inbound callbacks and mandatory consent work continue. | **Recovery gap.** GHL validates the shared-funding risk but its visible wallet behavior is not UCRM's approved safety boundary. |
| A rebilled location at zero balance stops outbound communications and directs the user to card/billing repair. | Insufficient organization credit stops normal outbound only; unavoidable inbound and STOP/START/HELP continue, and underfunded provider-billed inbound becomes Outstanding Communication Usage. | **Partial fit.** The user-facing “blocked because of balance” explanation is proven; GHL does not establish UCRM's approved inbound-debt treatment. |
| HighLevel has message/segment limits, ramp lockouts, compliance restrictions, contact DND, and a broad Pause Sub-Account action. | UCRM separates package SMS mode, organization preference, consent, registration, balance, spend caps, organization outbound pause, global outbound pause, and emergency provider controls. | **Scope conflict if collapsed.** GHL itself demonstrates that restriction causes differ; its broad account pause should not be treated as an SMS control. |
| Failed workflow SMS is not automatically sent after a restriction ends. | UCRM already requires current checks and deliberate recovery; restored service never releases a stale backlog automatically. | **Strong behavioral match.** |
| GHL shows A2P/Toll-Free status and correction paths but not one complete public provider-state model. | UCRM's owner model needs current saved state, provider-reported state, timestamps, safe provider errors, and controlled submission/resubmission. | **Evidence gap.** GHL validates the visible journey, not a complete canonical internal state machine. |
| HighLevel analytics covers at most 90 days in the cited dashboard and wallet summaries may lag up to 24 hours. | UCRM's approved immutable history and rate-versioned ledger are the source for historical money truth. | **Reporting gap.** GHL's dashboards are operational views, not evidence for long-term financial/audit retention. |

## 7. Smallest proven surface inventory, without implementation inference

The first-party evidence supports only the following minimal product-surface inventory:

1. **Phone Numbers:** number, type/capabilities, messaging-registration badge, and entry to configure or verify.
2. **Registration/Trust Center:** business and use-case submission, pending/approved/rejected outcome, required
   fixes, resubmission/appeal path, and proof that the number is linked after approval.
3. **Messaging Analytics:** sent/delivered/failed/received/opt-out summary, trends, source filters, failure reasons,
   and message-level logs.
4. **Messaging Limits/Restriction History:** current limit or ramp, warning/restriction reason, time, measured
   value, and recovery evidence.
5. **Billing and Usage:** balance, transaction history, category/location spend, drill-down, export, and pricing
   reference.
6. **Agency Controls:** new-location phone defaults, location limit override, rebilling/markup state, wallet
   alerts, and a separately named broad location pause/resume control.

Anything beyond these surfaces—including a complete provider state machine, automated contractor-card top-ups
for UCRM, automatic release of held work, or use of account pause as an SMS switch—is not established by this
research.
