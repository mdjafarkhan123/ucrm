# HighLevel SMS workflow behavior — Stage 5 research

Research date: 2026-09-12  
Scope: first-party HighLevel help center and changelog only. This note records observed product behavior for
planning; it does not propose UCRM behavior or implementation.

## 1. Choosing and adding an SMS step

### Documented facts

- A user opens or creates a workflow, chooses its trigger, and adds a **Send SMS** action at the desired place
  in the workflow. The action can be given a descriptive name so multiple SMS steps remain distinguishable.
  The workflow must be saved, tested, and published before live use.
  [HighLevel: Workflow Action — Send SMS](https://help.gohighlevel.com/support/solutions/articles/155000002474)
- HighLevel distinguishes an automatic **Send SMS** action from **Manual SMS**. Manual SMS creates a task in
  `Conversations > Manual Actions`; a person reviews and sends it. It can be assigned to a selected user, with
  documented fallbacks to contact owner and then Unassigned when access/availability prevents that assignment.
  [HighLevel: Workflow Action — Manual SMS](https://help.gohighlevel.com/support/solutions/articles/155000003289-workflow-action-manual-sms)
- Workflow recipients are selected by the workflow trigger rather than manually selected for every send.
  HighLevel gives form submission, appointment booking, and opportunity updates as example entry events.
  [HighLevel: Getting Started — Launch an SMS Campaign](https://help.gohighlevel.com/support/solutions/articles/155000005065)

### Gap / unknown

- The reviewed first-party material does not publish the complete current action-picker layout, search/filter
  behavior, or whether Send SMS is visibly grouped under a particular category in every builder version.

## 2. Editing message content, templates, and custom values

### Documented facts

- The Send SMS editor supports a written message body, dynamic/custom fields such as contact name,
  appointment time, and custom fields, and selection of an existing SMS template. Selecting a template fills
  the message content; HighLevel also documents SMS templates as reusable **snippets** available in workflows.
  [HighLevel: Workflow Action — Send SMS](https://help.gohighlevel.com/support/solutions/articles/155000002474)
  [HighLevel: SMS Templates (Snippets) — Overview](https://help.gohighlevel.com/support/solutions/articles/48000981405-sms-templates-snippets-overview)
- A user can enter a test phone number and send a test SMS before activation. The country selector defaults to
  the sub-account country; the user can choose another country and enter a local-format number.
  [HighLevel: Workflow Action — Send SMS](https://help.gohighlevel.com/support/solutions/articles/155000002474)
- The current help article describes links or attachment resources as URLs in the message. A later official
  changelog says supported workflow actions can instead upload a file or choose one from Media Storage, after
  which HighLevel validates type and size and carries the attachment with a copied action.
  [HighLevel: Workflow Action — Send SMS](https://help.gohighlevel.com/support/solutions/articles/155000002474)
  [HighLevel changelog: Media Storage Now Available in Workflows](https://ideas.gohighlevel.com/changelog/media-storage-now-available-in-workflows)
- The workflow SMS action also has an optional **Write with AI** flow: describe the use case, optionally select
  tone, generate or regenerate, review, and insert the result with **Use Message**.
  [HighLevel changelog: Workflow Action Update — SMS AI](https://ideas.gohighlevel.com/changelog/workflow-action-update-sms-ai)

### Gaps / unknowns

- The sources do not clearly say whether editing a message populated from a snippet changes only that action
  or also updates the saved snippet.
- The reviewed sources do not publish a complete current custom-value catalogue, missing-value preview rules,
  segment counter/encoding display, maximum composed-message length, or URL-shortening behavior for this action.
- The attachment help text and newer Media Storage changelog describe different UI generations. The changelog
  establishes the newer capability, but not which accounts/actions receive it or the exact current SMS/MMS
  attachment limits.

## 3. Sender and recipient behavior

### Documented facts

- A Send SMS action can explicitly select a **From Number** belonging to the sub-account. An action-level
  selection overrides user assignment, conversation continuity, and the account default. A workflow also has
  a Settings-level default From Number for its SMS actions.
  [HighLevel: How the “From” Number Is Chosen for SMS](https://help.gohighlevel.com/support/solutions/articles/48001152126)
  [HighLevel: Workflow Settings — Overview](https://help.gohighlevel.com/support/solutions/articles/48001239875)
- HighLevel's published sender order is: explicitly selected message/action number; sending user's assigned
  number; the number already used for the contact's conversation; then the account default outbound number.
  An SMS-incompatible assigned-user number falls back to the default. The sender actually used is visible in
  the sent message's Details.
  [HighLevel: How the “From” Number Is Chosen for SMS](https://help.gohighlevel.com/support/solutions/articles/48001152126)
- A workflow Send SMS action sends to the contact in that workflow execution. For contacts with multiple phone
  numbers, HighLevel says workflows always use the contact's **Primary** number unless otherwise configured;
  if no primary is explicitly chosen, the first stored number is treated as primary for outgoing messages.
  [HighLevel: Adding Multiple Phone Numbers for a Contact](https://help.gohighlevel.com/support/solutions/articles/155000000448-adding-multiple-phone-numbers-for-a-contact)

### Gaps / unknowns

- The Send SMS action article does not document a recipient-number selector or explain what “unless otherwise
  configured” means for an ordinary workflow SMS step.
- HighLevel's general sender article talks about a “sending user” even for automation but does not state which
  user identity an unattended workflow execution uses. Therefore the exact fallback between an assigned-user
  number and conversation number is not fully specified when no explicit workflow/action From Number is set.
- The sources do not specify what the action does when the contact has no phone number at execution time beyond
  the general fact that recipient-number failures surface as errors.

## 4. Scheduling, workflow windows, and quiet hours

### Documented facts

- Send SMS executes when the workflow reaches it, after any earlier triggers, conditions, and Wait steps.
  HighLevel schedules automation timing through separate **Wait** actions rather than a send-at control
  documented inside the Send SMS action.
  [HighLevel: Workflow Action — Send SMS](https://help.gohighlevel.com/support/solutions/articles/155000002474)
- Wait supports fixed durations, fixed or dynamic date/time, recurring weekly/monthly/yearly schedules,
  timing relative to appointments, service bookings, or invoice due dates, reply/action waits, and condition
  waits. Its advance window can restrict resumption to chosen days and hours.
  [HighLevel: Workflow Action — Wait](https://help.gohighlevel.com/support/solutions/articles/155000002470/)
- Workflow Settings provides one workflow-wide timezone mode: account timezone or each contact's timezone,
  falling back to account timezone when the contact has none. A workflow-wide Time Window specifies one start
  time, one end time, and included weekdays. Communication actions reached outside the window pause until the
  next valid slot; internal actions are not held. Different time windows or timezones per step are not
  supported by this setting.
  [HighLevel: Workflow Settings — Overview](https://help.gohighlevel.com/support/solutions/articles/48001239875)
- HighLevel separately offers scheduling for manual messages in Conversations: choose date, time, and timezone,
  see the scheduled message in the thread, and cancel it from message details. That changelog describes the
  conversation composer, not workflow SMS actions.
  [HighLevel changelog: Schedule Email & SMS Messages](https://ideas.gohighlevel.com/changelog/new-feature-schedule-email-sms-messages)

### Gaps / unknowns

- No reviewed first-party source documents a separate automatic SMS “quiet hours” engine for workflows beyond
  the workflow Time Window/Wait mechanisms. A 2025 quiet-hours changelog explicitly said SMS support was still
  coming and that workflow calls used each workflow's settings; it is not evidence of current workflow-SMS
  enforcement.
  [HighLevel changelog: Quiet Hours for Outbound Calls](https://ideas.gohighlevel.com/changelog/quiet-hours-for-outbound-calls-via-labs)
- The sources do not state how contacts already waiting are recalculated when a workflow's time window,
  timezone, or Wait configuration is edited, except that changing the account timezone does not affect
  contacts already running and applies only to new workflow entries.
- A time-window-delayed workflow action is documented as paused and later resumed, but the reviewed sources do
  not establish whether Conversations shows a future scheduled-message bubble for that pending action.

## 5. Replies, DND, consent, and restrictions

### Documented facts

- **Stop on Response** is a workflow-wide option. When enabled, HighLevel ends the workflow for the individual
  contact if that contact replies to a message sent by that specific workflow; when disabled, the contact
  continues. It applies across the workflow's communication channels, not only SMS.
  [HighLevel: Workflow Settings — Overview](https://help.gohighlevel.com/support/solutions/articles/48001239875)
- A Wait step can alternatively hold for the contact to reply on SMS (or another chosen channel), optionally
  with a timeout. HighLevel requires an earlier Send Email/SMS action before this reply wait.
  [HighLevel: Workflow Action — Wait](https://help.gohighlevel.com/support/solutions/articles/155000002470/)
- SMS DND is channel-specific and blocks further outbound SMS attempts. Standard opt-out replies can activate
  it. HighLevel says communication steps conflicting with the contact's DND are skipped while non-conflicting
  workflow actions continue.
  [HighLevel: LC Phone Messaging Policy](https://help.gohighlevel.com/support/solutions/articles/48001213941)
  [HighLevel: Workflow Trigger — Contact DND](https://help.gohighlevel.com/support/solutions/articles/155000002673)
- HighLevel's policy requires valid consent, sender identification in the initial outbound message, clear
  opt-out language, and no further SMS after consent is revoked unless the contact validly opts back in.
  [HighLevel: LC Phone Messaging Policy](https://help.gohighlevel.com/support/solutions/articles/48001213941)
- Account-level SMS Compliance Settings can automatically append missing sender identification and opt-out text
  to the first outbound message in a conversation. An optional 1–60 day cadence re-adds those lines to the next
  outbound message when due and missing; complete opt-out wording already in the message suppresses duplication.
  [HighLevel: Configure SMS Compliance Settings](https://help.gohighlevel.com/support/solutions/articles/155000004684/)
- Account/provider restrictions are different from contact DND. If a workflow reaches Send SMS while outbound
  SMS is restricted, the SMS can fail; it is not automatically retried when the restriction ends, and the
  contact is not guaranteed to remain held at that step.
  [HighLevel: LC Phone Messaging Policy](https://help.gohighlevel.com/support/solutions/articles/48001213941)

### Gaps / unknowns

- HighLevel's sources are inconsistent in terminology: the DND workflow guide says conflicting communication
  steps are **skipped**, while the messaging policy says an attempted SMS with active DND can be **blocked with
  a DND error**. They do not clearly define when the UI/log uses Skipped versus Failed/Error for DND.
- The reviewed sources do not document whether Stop on Response cancels an already-created manual scheduled
  conversation message, as distinct from removing the contact from the workflow.
- The policy states that valid consent is required but does not document a universal workflow-action field that
  stores or validates consent evidence before every send. DND/opt-out blocking is documented; a broader
  per-message consent-proof check is not.

## 6. Visible results and statuses

### Documented facts

- Sent workflow messages appear in Conversations. Message Details can link directly to the related workflow
  execution, and it also shows the business number used.
  [HighLevel: Improved Execution Logs & Enrollment History](https://help.gohighlevel.com/support/solutions/articles/155000003992-execution-logs-enrolment-history-enhancements)
  [HighLevel: How the “From” Number Is Chosen for SMS](https://help.gohighlevel.com/support/solutions/articles/48001152126)
- Workflow Execution Logs expose each contact's path, action name/type, error highlighting, skipped nodes, and
  in-progress/entry/exit state. Contacts and skipped SMS steps in a contactless Scheduler run are explicitly
  shown as Skipped while downstream contactless actions continue.
  [HighLevel: Improved Execution Logs & Enrollment History](https://help.gohighlevel.com/support/solutions/articles/155000003992-execution-logs-enrolment-history-enhancements)
  [HighLevel: Workflow Trigger — Scheduler](https://help.gohighlevel.com/support/solutions/articles/155000006653-workflow-trigger-scheduler)
- In Conversations, an outbound SMS delivery failure is marked **Unsuccessful** with a red warning indicator.
  Opening it shows the numeric error code and available explanation. HighLevel's troubleshooting guide also
  distinguishes **failed** and **undelivered** statuses, and says workflow failures and error codes are visible
  in Workflow Logs. A Messaging Error — SMS trigger can react to selected undelivered/error codes.
  [HighLevel: Understanding Common SMS Delivery Errors](https://help.gohighlevel.com/support/solutions/articles/48001208912)
  [HighLevel: Troubleshooting SMS Delivery Issues](https://help.gohighlevel.com/support/solutions/articles/48000981696)
- Workflow-disabled actions are visibly greyed out with a Disabled tag and are logged as Skipped; downstream
  reachable actions continue.
  [HighLevel: Pause Workflow Actions](https://help.gohighlevel.com/support/solutions/articles/155000006693-pause-workflow-actions)

### Gaps / unknowns

- The reviewed first-party sources do not publish one canonical lifecycle or status vocabulary for workflow SMS
  covering queued/scheduled, sending, sent, delivered, failed, undelivered, skipped, canceled, and replied.
- They do not clearly state whether a provider-accepted message is labeled Sent before a carrier receipt,
  whether Delivered replaces Sent, or whether Failed and Undelivered are separate durable states versus UI
  wording for different error stages.
- HighLevel documents future scheduled-message visibility and cancellation only for manually scheduled
  Conversations messages. It does not document an equivalent per-message Scheduled status or cancel control
  for a workflow contact waiting before a future SMS action.
- Execution Logs show errors and skipped nodes, but the reviewed sources do not list the exact reason text stored
  for each skip case (DND, missing recipient, disabled action, past-date rule, or contactless run).

## Evidence summary

HighLevel's well-documented product pattern is: add an automatic or manual SMS action; compose or start from a
snippet; personalize with runtime values; optionally test; choose a workflow/action sender; use Wait steps plus
one workflow timezone/time window to control timing; stop or wait on replies; enforce SMS DND and provider
restrictions at execution; and investigate outcomes in Conversations plus Workflow Execution Logs. The exact
status state machine, DND skip-versus-failure labeling, unattended sender fallback, and visibility/cancellation
of future workflow SMS are not fully specified in the reviewed first-party sources.
