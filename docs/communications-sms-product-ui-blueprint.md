# Communications SMS Product UI Blueprint

**Status:** Approved by Jafar on 2026-09-13  
**Scope:** A2 product UI only — no implementation plan, schema, provider work or code  
**Evidence:** Live HighLevel subaccount walkthrough on 2026-09-13, current first-party HighLevel material,
approved UCRM behavior contracts, existing UCRM screen/component patterns, and the UCRM design system

## Product direction

SMS extends the Communications product already in UCRM. It does not create a separate inbox, automation
builder, settings shell, usage dashboard family or Jafar control room.

Use the mature HighLevel separation:

- **Conversations** is where staff talk to one customer and diagnose one message.
- **Automation** is where an owner designs unattended SMS behavior and reviews its executions.
- **Phone & SMS** is where a contractor understands registration, numbers and sending readiness.
- **SMS usage** is where a contractor understands balance and charges.
- **Jafar's existing organization and Operations surfaces** are where the platform owner controls provider,
  commercial and emergency truth.

HighLevel supplies the proven structure and interaction ideas. UCRM uses its own visual system: Inter type,
semantic colors, generous but efficient spacing, bordered `SectionBlock` groups, restrained shadows, clear
status badges, Tabler icons, accessible controls and automatic dark mode. The result should feel as polished
as HighLevel without copying its branding or its canvas-builder complexity.

## Navigation and screen inventory

| Audience | Existing home | Destination or extension | Purpose |
| --- | --- | --- | --- |
| Staff | Communications | Existing conversation workspace | Send, receive and diagnose SMS with other channels |
| Automation manager | Settings → Automation | Existing builder and automation detail | Configure Send SMS and review scheduled/delivery outcomes |
| Communications manager | Settings → Communications | **Phone & SMS** | Registration, numbers, readiness, mode, hours and holds |
| Communications manager | Settings → Communications | **SMS usage** | Balance, top-ups, charges and lean health |
| Jafar | Existing organization detail | Communications workspace | One organization's readiness, numbers, credit, rates and pause |
| Jafar | Existing Operations area | Communications controls | Platform reserve, provider health, alerts and global pause |

The Settings home adds only two cards: **Phone & SMS** and **SMS usage**. Their badges show the most useful
current truth: Ready, Needs setup, Pending review, Restricted, Paused or Low balance. Staff without management
permission do not see these destinations.

## 1. Conversations SMS

### Desktop composition

Keep the existing UCRM three-pane workspace:

```text
┌ Conversation list ┬ Customer timeline and composer ┬ Customer context ┐
│ My / Team inbox   │ Name · handling actions         │ Contact methods  │
│ Search + filters  │ Mixed-channel history           │ Related work     │
│ Unread / All      │                                 │ Follow/assignment│
│ Dense rows        │ [Email] [SMS] [Website Chat]    │                  │
│                   │ To …  From …                    │                  │
│                   │ Message                         │                  │
│                   │ tools · segments · cost · Send  │                  │
└───────────────────┴─────────────────────────────────┴──────────────────┘
```

The existing channel tabs remain above the composer. SMS appears only when the organization has SMS access and
the viewer may use Conversations. Selecting SMS does not navigate or replace the timeline.

### SMS composer

The composer shows, in this order:

1. **To** — selected saved customer number. A permitted user may choose another saved SMS-capable number.
2. **From** — selected eligible business number. Show friendly label, number and why it is selected: Continued
   conversation, Assigned to you, or Organization default. A permitted user may change it.
3. **Message** — plain text with variables resolved before send where the context supports them.
4. **Tools** — Snippet, picture/file, and secure-link path. Snippets insert editable text.
5. **Impact line** — live characters, estimated segments and estimated retail cost. Explain Unicode or picture
   pricing only when it changes the estimate.
6. **Send** — one primary action. The arrow/menu may expose approved scheduling when available; it never hides
   the normal Send action.

Required sender identification and opt-out wording appears in a small preview line below the message when UCRM
will append it. Staff see the final estimated character/segment impact before sending.

### Availability and blocked sending

Do not remove a known SMS conversation merely because it cannot send. Keep the channel visible and replace Send
with one plain, actionable reason:

- Add a customer mobile number
- Choose which customer this number belongs to
- SMS is not included in this business's plan
- SMS is disabled for this business
- Registration is awaiting review
- This number is not ready for SMS
- Customer opted out — texting is legally blocked
- SMS is on hold for this customer
- Outside allowed hours — earliest send time shown
- Not enough Communication Balance — link to SMS usage
- Business sending is paused — reason and manager path
- SMS is temporarily unavailable — safe retry or support path

Legal opt-out, ordinary DND/hold, technical suppression, balance, registration and platform pause remain
visually distinct. Never summarize all of them as a generic error when the cause is known.

### Timeline and delivery states

SMS uses the same chronological timeline as email and Website Chat. Every bubble shows channel, time and origin
where useful. Outbound states are:

| State | Bubble treatment | Available action |
| --- | --- | --- |
| Sending | Quiet progress label | None; prevent duplicate click |
| Queued | Neutral clock badge | Open details |
| Scheduled | Neutral badge plus send time | Open details; cancel only when still safely cancellable |
| Sent | Muted check | Open details |
| Delivered | Success double-check | Open details |
| Checking | Warning badge: delivery uncertain | Check status; no blind resend |
| Failed | Critical badge and short reason | Fix issue, then deliberate retry when safe |
| Cancelled | Inactive badge | Open details |

SMS never shows Read. A workflow skip creates an Automation history entry but no fake message bubble.

### Message details dialog

Extend the existing `MessageDetailsDialog` pattern. It contains:

- message status and plain explanation;
- customer and business phone numbers;
- sent/received time in the contractor timezone;
- human, workflow or system origin;
- provider/carrier evidence that is safe to show;
- segment count, estimated/final retail charge and adjustment when known;
- attachments or secure links;
- failure code plus useful explanation;
- **View automation execution** for automated messages;
- **Check status** for uncertain delivery;
- deliberate **Retry** only when the product can prove the first attempt did not succeed.

Do not expose Twilio credentials, internal tenant identifiers or raw unsafe provider payloads.

### Incoming identity exceptions

- **One customer match:** open the normal conversation.
- **No match:** show the auto-created Lead and Unassigned conversation normally.
- **Several matches:** show a persistent **Needs identification** banner above the timeline. Reply is disabled.
  Primary action: **Choose customer**. Secondary action: **Create new lead**. The selection dialog searches
  existing clients first and explains that required STOP/START/HELP handling already occurred.

### Responsive boundary

- At tablet width, hide the customer rail and open the same content in the existing information drawer.
- On a phone, show the conversation list first. Selecting a row opens the thread full-screen with Back.
- The composer stays pinned above the mobile safe area; To/From collapse into one **SMS details** row that opens
  a bottom sheet.
- Timeline filters and handling actions move into an overflow menu; Send remains visible.
- No desktop information is lost, but secondary context is revealed rather than shown simultaneously.

## 2. Automation Send SMS

### Builder composition

Keep UCRM's approved linear builder and existing `SectionBlock` sequence. Do not copy HighLevel's node canvas.
Inside **Then do this**, **Add an SMS** sits beside **Add a wait** and **Add an email**. Each step stays expanded
while being edited and collapses to a readable summary when valid.

The Send SMS step contains:

- Step name, default **Send SMS**
- **To:** Customer's primary SMS number (read-only rule, with explanation)
- **From:** Continue an eligible conversation number, otherwise Organization default; an authorized manager may
  pin another eligible number
- Reusable reply picker that copies editable text
- Message editor and approved variable controls
- Secure-link attachment field; no automated MMS in A2
- Live character, segment and estimated-cost line
- **Send test SMS** to the signed-in authorized user's verified team phone

A test is labelled **Real test — normal SMS charges apply**. It has sending, success and failed states and never
changes the recipe draft automatically.

### Wait and sending-window relationship

- Wait remains a normal ordered step and owns intentional delays.
- An optional recipe-level **Sending window** appears in a **Communication rules** block below the steps.
- The block shows organization timezone, permitted days/start/end and the explanation: workflow timing may be
  narrowed here; legal and business SMS hours still apply at send time.
- A collapsed summary rail names both: `Wait 2 days → Send SMS` and `Sending window: Mon–Fri, 9am–5pm`.

### Save and activation review

The existing pinned form action bar continues to own Cancel and Save draft. Activation review adds an SMS
section with:

- maximum SMS sends one customer can receive in one enrollment;
- selected sender rule;
- sending window;
- estimated segment impact using the current sample, clearly labelled as an estimate;
- number/registration readiness;
- available balance and applicable cap/pause status;
- test status, when a test was run.

True blockers disable **Turn on** and link to the exact Settings fix. Warnings require acknowledgment only when
the user can safely proceed.

### Automation detail and history

Reuse Overview, History and Versions. Overview's summary rail displays SMS steps and sender/window rules.
History rows use plain outcomes:

- Waiting until [time]
- Scheduled for [time]
- SMS sent / delivered
- Skipped — customer has no primary mobile number
- Skipped — customer opted out
- Failed — insufficient balance
- Failed — sending restricted
- Needs checking — provider outcome uncertain

Each row links to the customer Conversation when a message exists. A message bubble links back to this exact
enrollment/execution. Revealed History continues to prefetch on hover and show a skeleton if needed.

### Responsive boundary

Automation authoring remains desktop-first. At smaller widths it may remain horizontally constrained with a
clear **Use a larger screen to edit this automation** message. Automation detail/history is responsive and
readable on tablet and phone; editing parity is not required for A2.

## 3. Contractor Settings — Phone & SMS

### Page hierarchy

Use one page with a readiness summary followed by four `SectionBlock`s:

```text
Phone & SMS                                      [Overall status]
Understand what is ready and what needs attention.

┌ Readiness ──────────────────────────────────────────────────────┐
│ Plan mode · Registration · Sending number · Balance/hold summary│
│ One primary next action                                         │
└──────────────────────────────────────────────────────────────────┘

┌ Registration ┐  ┌ Phone numbers ┐  ┌ Sending rules ┐  ┌ Holds ┐
```

#### Readiness

Show four compact facts: SMS mode, registration, ready numbers and outbound availability. The primary action is
the next real step only: Start registration, Fix registration, Request a number, Finish number setup, Add credit
or Review pause. When ready, show no decorative action.

#### Registration

Show business/use-case summary, state, submitted/updated times and provider-owned review truth. States: Not
started, Draft, Submitted, Pending, Approved, Rejected, Needs information and Propagating. Rejected/Needs
information shows **View required fixes**. Inputs use an explicit Save/Submit action; provider submission impact
is confirmed. Approval is not called Ready until a number is linked and eligible.

#### Phone numbers

Responsive table/list: friendly name, phone number, Voice/SMS/MMS capability, assignment/default, registration
badge and sending readiness. Row details show continuity use and safe provider state. Contractor actions are
requests—Request number, Make default, Request release or Request replacement—when Jafar/provider ownership
requires fulfillment. Impactful requests explain affected conversations before confirmation.

#### Sending rules

Show organization SMS preference within the plan's maximum mode, business SMS hours, timezone and the approved
hold behavior. Legal recipient-local hours remain a non-editable explanation. Save is explicit.

#### Blocked numbers and holds

Searchable list of ordinary contractor holds and technical blocks with reason, source, date and allowed recovery.
Legal opt-out evidence is read-only and never presented as a normal unblock toggle.

### Visible restricted states

- Not included in plan: read-only explanation and upgrade/contact path
- Notifications only: two-way composer unavailable but approved notification use remains
- Registration pending: show expected next step without promising a date
- Registration rejected: required fixes and resubmit path
- No ready number: history preserved; outbound blocked
- Organization/platform pause: distinct banner with reason, time and who can resolve it
- Provider unavailable: stale-state timestamp and retry/support path

### Responsive boundary

Desktop uses summary cards and tables. Tablet uses two-column summaries. Phone uses one-column cards and number
rows rather than a horizontally scrolling table. Registration forms and confirmation dialogs remain fully usable.

## 4. Contractor Settings — SMS usage

Keep money separate from readiness and delivery diagnosis.

### Page composition

1. **Balance strip:** Available Communication Balance, reserved pending charges, outstanding usage and current
   SMS availability.
2. **Add credit:** primary action **Request top-up**. Explain that the request creates no usable credit until
   Jafar confirms payment.
3. **Usage summary:** This month retail charge, segments, messages and adjustments. This is deliberately lean.
4. **Messaging health:** Sent, Delivered, Failed, Received and Opt-out rate for a short selected period, with
   **View messages** linking to filtered Conversations—not a duplicated analytics product.
5. **Ledger:** reverse-chronological entries with date, type, reference, purchased/promotional bucket, debit or
   credit, balance after and status. Filters: date, entry type and status.
6. **Top-up requests:** Pending, Confirmed, Declined or Cancelled with submitted/decided evidence.

Unknown or corrected charges remain visible. Pending provider cost is labelled Pending, not finalized. A later
correction is a new ledger entry and never silently rewrites history.

### Empty and failure states

- No usage yet: explain that charges appear after SMS activity; keep Request top-up visible.
- No ledger matches: clear filters.
- Balance unavailable: keep history visible and disable spending actions that require current truth.
- Low balance: warning with estimated effect, never a false delivery guarantee.
- Zero balance: critical outbound block with Request top-up; required inbound/consent processing explanation.

## 5. Jafar organization controls

Extend the existing organization detail workspaces; do not add a new owner dashboard family.

### Integrations / Communications workspace

Add one **SMS** provider-readiness card beside existing communications providers. Its safe summary shows:

- Twilio subaccount state and last checked time
- registration state
- ready/total numbers
- effective SMS mode
- organization pause/global pause effect
- current balance and outstanding usage
- one next safe action

Below it, existing card/action patterns provide these focused blocks:

- **Registration:** inspect safe submitted data, provider result, required fixes, submit/resubmit/review history
- **Numbers:** provision/request, assign, default, release/replace with impact review
- **Commercial access:** effective entitlement/mode, rate version, purchased/promotional credit and caps
- **Sending safety:** organization pause/resume, reason, affected queued work and no-stale-release warning
- **Recovery:** reconcile uncertain delivery/charge, provider resync and controlled proof review

Every mutation opens an impact dialog, requires a reason where operationally meaningful, and records history.
Secrets and raw credentials never appear.

### Existing History and recovery

SMS events join the existing organization history using plain sentences: registration submitted/result changed,
number provisioned/released/default changed, credit confirmed/adjusted, rate changed, pause/resume, proof review
and provider reconciliation. Filters may include Communications/SMS without creating a second audit page.

## 6. Jafar Operations — Communications

Use the existing Operations navigation. Add an SMS section with:

- platform outbound status and emergency Pause/Resume;
- Twilio parent reserve status and threshold alert;
- provider/webhook health and last healthy time;
- counts of organizations restricted, paused, low-balance or registration-blocked;
- unresolved uncertain deliveries/charge discrepancies;
- a searchable organization list that deep-links to that organization's Communications workspace.

This is an operational control surface, not forecasting or a full analytics suite. A global pause requires impact
review and a reason, preserves inbound and STOP/START/HELP work, and never automatically releases stale messages.

## 7. Permissions

| Capability | Ordinary permitted staff | Communications manager | Owner/Admin | Jafar |
| --- | --- | --- | --- | --- |
| View assigned/followed Conversations | As granted | As granted | Yes | Support boundary only |
| Send SMS | Explicit send capability | If granted | Default eligible | No routine impersonation |
| Change customer To number | If send capability allows | Yes | Yes | No routine use |
| Change business From number | Only eligible assigned choices | Yes | Yes | Provision/control only |
| Resolve ambiguous identity | Manage-conversation capability | Yes | Yes | Recovery only |
| Manage registration/numbers/rules | No | Yes | Yes | Provider-owned actions |
| View SMS usage | No unless granted | Yes | Yes | Organization support view |
| Request top-up | No unless granted | Yes | Yes | Confirm/decline only |
| Change rates/credit/pause/provider state | No | No | Organization preference only | Yes |

Restricted users see only the message/channel facts required for their work. Financial data follows existing
pricing/financial permissions; sender eligibility never grants access to hidden customer or work records.

## 8. Shared loading, error and recovery rules

- Render the page shell immediately; loading belongs to the specific pane, section, dialog or revealed tab.
- Cached content remains visible during background refresh with a quiet refreshing treatment.
- A failed list or section keeps unaffected areas usable and offers Retry locally.
- Disabled actions always explain why through visible text or an accessible tooltip/popover.
- Stale provider truth shows **Last checked** and does not claim Ready.
- Empty states teach the next safe step; they do not advertise unbuilt features.
- Confirmation dialogs name the affected customer, number, organization or queued-message count before an
  impactful action.
- Success uses a toast and refreshed visible state. Validation appears beside the field; operational failure
  uses a plain banner with a recovery path.

## 9. Explicit HighLevel/UCRM differences

| HighLevel pattern | UCRM decision |
| --- | --- |
| Node-canvas workflow builder | Keep UCRM's simpler ordered linear builder |
| AI writer in SMS action | Excluded from A2 |
| Automated MMS | Excluded from A2; secure links only |
| Staff/assignment-first sender behavior in some material | Existing conversation continuity wins; new manual conversation uses assigned/default rule |
| Workflow sender may follow staff defaults | Automation continues conversation/default or uses an explicitly pinned number; no staff-assignment inference |
| Wallet auto-recharge and card repair | Offsite top-up request; balance changes only after Jafar confirms payment |
| Large Messaging Analytics suite | Lean contractor health summary linking back to Conversations |
| Broad subaccount pause | Separate SMS-specific organization and platform outbound pauses |
| HighLevel visual styling | UCRM tokens, accessibility, dark mode and contractor-focused language |

## 10. Product UI acceptance checks

The UI is complete only when a reviewer can verify all of the following from the blueprints:

1. A staff member can understand the selected customer number, business number, estimated segment/cost impact
   and final appended wording before sending.
2. Every unavailable SMS state explains its distinct cause and next action.
3. Queued, scheduled, sent, delivered, checking, failed and cancelled states remain truthful; no Read receipt is
   invented.
4. Ambiguous inbound identity cannot be replied to until safely resolved.
5. An automation author can configure content, variables, sender, test, Wait and sending window without mistaking
   workflow preference for the legal boundary.
6. Activation review blocks a recipe that cannot safely send and links to the exact fix.
7. Conversation messages and automation executions deep-link to one another.
8. Registration approval and number readiness are visibly separate.
9. Balance, delivery health, compliance restriction and pauses are visibly separate.
10. Contractor top-ups never look instantly spendable before Jafar confirms them.
11. Jafar can inspect and recover one organization without exposing secrets or creating a duplicate dashboard.
12. Conversations and everyday settings work responsively; automation editing remains honestly desktop-first.
