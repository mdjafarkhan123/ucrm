# SMS settings and owner controls — product proposal

Status: Approved by Jafar, 2026-09-12. Durable behavior is recorded in the contractor-settings, Platform Owner,
and unified-inbox contracts. No coding is authorized by this approval.

Stage 6 is the final A2 functional-behavior stage. It organizes already-approved SMS readiness, balance, provider
and recovery rules into the smallest useful contractor and Platform Owner journeys. Product UI planning follows
as Stage 7; this document does not introduce a new commercial model or implementation plan.

## GHL pattern and the smaller UCRM shape

HighLevel separates Phone Numbers, Trust Center registration, Messaging Analytics, Restriction History, wallet
usage and agency controls. [1][2][3][4] UCRM keeps those responsibilities separate but does not create six new
destinations:

- contractors use the already-approved **Phone & SMS** and **SMS usage** Settings pages;
- Jafar uses the existing organization **Integrations**, **Commercial access**, and **History and recovery**
  areas, plus the existing platform Operations/Communications health surface;
- Conversations and Automation continue to show message-level outcomes where the daily work happens.

Registration, an outbound restriction, insufficient contractor credit, and a platform or organization pause are
different conditions. Never collapse them into one vague "SMS not working" state.

## Contractor: Phone & SMS

Only organization owners and administrators manage this page. Other authorized staff see message-level delivery
information in Conversations without seeing provider setup, business-wide controls, or money.

### Readiness summary

Use plain customer-facing states rather than exposing every provider code:

| State | What it means and what the contractor can do |
| --- | --- |
| **Not included** | The organization's effective package/mode does not permit this SMS capability. Explain the limit; do not show a dead setup form. |
| **Needs setup** | SMS is eligible but no setup has started. **Start setup** opens the required business and messaging-purpose questions. |
| **Waiting for your information** | Required legal business, website, consent, sample-message, or use-case information is incomplete. Link to the exact missing item. |
| **Under review** | The contractor submitted and attested the information; Jafar or the carrier is reviewing it. Show the submitted purpose and last update without promising an approval date. |
| **Action needed** | Show each safe rejection or correction reason and the fields needing attention. The contractor corrects and re-attests; Jafar resubmits. |
| **Finishing setup** | Registration is approved but the selected number is still being linked or provider changes are propagating. Texting remains unavailable until the real readiness check passes. |
| **Ready** | At least one assigned sender is registered and live for the capability promised. Other live gates such as consent, balance, mode and quiet hours still apply per message. |
| **Outbound paused** | Setup/history remain available and inbound/required consent processing continues. Show whether the cause is organization choice, safety control, balance, or provider restriction and who can resolve it. |

### What the page contains

- assigned business numbers with friendly label, number, country/type, Voice/SMS/MMS capability, registered use
  case, readiness, default/continuity role, and any renewal warning;
- **Request number**, **Request port**, **Request replacement**, or **Request release** when eligible. These create a
  reviewed request because Jafar owns and funds the provider account; contractors do not directly purchase or
  destroy platform-managed numbers;
- the organization's chosen SMS mode, limited to the maximum allowed by its package or Jafar override;
- business-wide SMS hours/quiet hours and the timezone used;
- blocked customer numbers and ordinary business holds, while legal STOP remains locked to valid customer
  re-opt-in or controlled proof review;
- the current registration submission, attestation, required fixes, provider outcome, and last checked time.

Number replacement, porting or release always previews affected conversations, scheduled messages, automations,
recurring charges, and the continuity impact before confirmation. Historical messages keep the number used at the
time.

## Contractor: SMS usage

Keep message health and money visually separate on the same page.

### Money

- show **Spendable balance** first, then Purchased Credit, Promotional Credit with expiry, Reserved Credit and
  Outstanding Communication Usage separately;
- show the current included allowance, current published retail rates, recent usage, and an approximate domestic
  SMS count clearly labelled as an estimate because encoding, destination, sender and carrier fees vary;
- warn when balance crosses the approved low threshold, recent use suggests fewer than seven days, or an upcoming
  number/registration renewal is not covered;
- **Request top-up** records the requested dollar amount and offsite payment reference/details. It creates no credit
  until Jafar verifies and confirms the amount received;
- top-up history shows Awaiting confirmation, Confirmed, Rejected or Cancelled. A contractor may cancel only an
  awaiting request; confirmed money is corrected through a new recorded adjustment, never by editing history;
- the ledger shows allowances, top-ups, reservations, charges, releases, adjustments and refunds with date,
  description, amount and resulting balance. Contractors see retail charges only, never Twilio cost or margin.

There is no automatic card recharge, contractor card storage, or HighLevel-style rebilling in A2.

### Messaging health

- show Sent, Delivered, Failed, Received and Opt-out totals for the selected period;
- filter by date, business number and source such as Conversations or Automation;
- open a failed item to the existing customer conversation/message details and its safe reason;
- show current outbound restriction or usage cap separately from delivery-rate and opt-out trends;
- do not build forecasting, carrier benchmarking, or a second copy of Conversations history.

## Jafar: organization controls

Use the existing `/jafar/organizations/[organizationId]` areas.

**Integrations** shows the contractor's safe setup answers, attestation, Twilio subaccount reference, assigned
numbers, registration/use-case state, last provider check, effective SMS mode, current restriction or pause, and
the next required action. Jafar may provision/assign a number, review and submit/resubmit registration, request
contractor corrections, and begin a reasoned replacement/port/release flow. Carrier/provider decisions are never
shown as Jafar's approval.

**Commercial access** shows the package maximum, any reasoned effective-dated SMS-mode/allowance/cap exception,
Purchased/Promotional/Reserved/Outstanding balances, current retail-rate version, and renewal exposure. Jafar may
confirm or reject top-up requests, record the amount actually received, and make a reasoned adjustment or refund.
The balance itself is never directly editable.

**History and recovery** records registration attempts, provider outcomes, number lifecycle, top-ups, credits,
rate/limit changes, pauses, failures and recovery actions without provider secrets or unnecessary message content.
Safe retry first reruns current checks; uncertain or stale messages are never blindly resent.

## Jafar: platform safety and rates

The existing Operations/Communications health surface shows only what is needed to run the shared service:

- Twilio parent balance and protected reserve, total contractor purchased-credit liability, normal outbound state,
  oldest queued work, callback/reconciliation health, recent failure/opt-out spikes and organizations needing
  attention;
- global outbound pause/resume and organization-specific outbound pause/resume as separate reasoned actions;
- organization daily spend/segment caps and unusual-usage or pumping alerts;
- current and future-dated retail rates by supported destination/sender/message unit, with impact preview. New
  rates affect new sends only; historical charges retain their original rate;
- provider cost and contractor retail revenue/margin visible only to Jafar.

A broad provider-subaccount suspension is an emergency containment action, not the normal balance, package or SMS
pause. Inbound callbacks and required STOP/START/HELP handling remain protected wherever the provider allows it.
No new standalone owner dashboard family is needed.

## Minimum real launch scenarios

A2 is not complete until these product journeys work with real provider evidence for each enabled country/sender
combination:

1. An eligible contractor submits truthful setup information; Jafar provisions a number and registration moves
   through review to genuinely ready.
2. A rejected or incomplete registration shows useful fixes, correction, renewed attestation and resubmission.
3. Manual Conversations SMS sends and receives on the promised number; STOP, START and HELP behave correctly.
4. Automation schedules around its workflow window and legal quiet hours, then visibly sends, skips or fails
   without duplicate messages or charges.
5. Zero contractor balance blocks normal outbound but preserves inbound and required consent handling; a confirmed
   offsite top-up restores only still-valid work and never releases a stale backlog.
6. A contact opt-out, organization pause, global pause, provider restriction and uncertain send each show their
   own cause and safe recovery path.
7. Usage, retail charges, provider costs, reservations and later corrections reconcile without directly editing
   balances or rewriting history.
8. An underfunded renewal receives its warning and 30-day protection; replacement, port or release requires impact
   review and preserves historical number identity.

Passing one US text does not prove global readiness or capacity. Enable only country/sender/use-case combinations
that pass their own registration, two-way, consent, delivery, failure, billing and recovery checks.

## Approved product choices

Approval confirms these five deliberately small choices:

1. two contractor pages and existing Jafar surfaces replace GHL's many separate destinations;
2. contractors request number lifecycle changes while Jafar performs provider-owned actions;
3. offsite confirmed top-ups remain the only A2 funding path—no cards or auto-recharge;
4. the plain readiness states above summarize provider detail without hiding the true cause;
5. A2 ships the stated usage totals and failure drill-down, not a large analytics or forecasting suite.

## Sources

1. [HighLevel phone-number setup](https://help.gohighlevel.com/support/solutions/articles/155000003226) and [A2P registration](https://help.gohighlevel.com/support/solutions/articles/155000002380)
2. [HighLevel Messaging Analytics](https://help.gohighlevel.com/support/solutions/articles/155000002625)
3. [HighLevel Restriction History](https://help.gohighlevel.com/support/solutions/articles/155000003568) and [Messaging Policy](https://help.gohighlevel.com/support/solutions/articles/48001213941)
4. [HighLevel communications spending](https://help.gohighlevel.com/support/solutions/articles/48001225291-how-to-analyze-an-agency-s-spending-on-lc-communications) and [wallet/rebilling](https://help.gohighlevel.com/support/solutions/articles/155000002095)

The complete first-party evidence and documented GHL/UCRM conflicts are in
`docs/research/ghl-sms-stage6-settings-owner-controls.md`.

## Approval recorded

Jafar approved all five Stage 6 choices on 2026-09-12. This completes A2 functional-behavior planning. After
Jafar clarified that campaigns also include product UI, Stage 7 UI research and blueprints were added before the
separate implementation-planning gate. No code or provider change is authorized.
