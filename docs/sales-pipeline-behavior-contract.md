# Sales Pipeline behavior contract

Status: Revision 3 approved by Jafar on 2026-10-01. Earlier approvals: 2026-08-18, then the unified board and
stage-customization revision on 2026-08-24. Amended by Jafar on 2026-10-02: the conversion counting rules,
Won finishing open Tasks, and ticking a Task off from the Schedule.
Owner: Sales Pipeline campaign

## Purpose

The Pipeline helps contractors see and advance open commercial work from Request through Quote. It is a sales
view, not a replacement status machine and not an operational Job board.

Industry evidence and deliberate differences are recorded in
`docs/research/contractor-crm-sales-pipeline-comparison.md` and the independent source check in
`docs/research/pipeline-independent-source-check-2026-10-01.md`.

## Opportunity identity

Jobber's current behavior is the reference. Where the earlier UCRM opportunity model disagreed with it, Jobber
wins.

- Opportunities are only ever generated from real work. Staff never create one by hand.
- Every Request automatically has exactly one Opportunity, created with the Request.
- Every Quote will automatically have exactly one Opportunity, created with the Quote in Part 5.
- A Job created without a Request or Quote creates one closed-only **Direct job** Opportunity. It never appears
  on the active board; it exists so Sales Outcomes counts genuinely booked work without inventing a Request or
  Quote. It is reported separately and excluded from Request/Quote conversion percentages.
- Converting a Request directly to a Job marks that Request's Opportunity Won. Creating a Job from a Quote that
  is already Won does not create a second win.
- **One Opportunity does not continue from Request to Quote.** A Request shows as a Request card. When it
  converts, that card leaves the Request stages, and the resulting Quote appears as its own card in Draft.
  The two are separate cards for the same underlying commercial thread, exactly as Jobber shows it.
- Request, Assessment, and Quote remain the source of truth for their own states and actions. A pipeline stage
  is a projection of those states, never a second editable status.
- A card carries no state that its source record cannot explain.

## First-release board

The board is one left-to-right commercial journey with five visible columns by default:

**New requests → Assessment → Draft → Awaiting response → Changes requested.**

Requests and Quotes remain visibly identified and remain separate source records underneath. A subtle boundary
between Assessment and Draft marks the Request-to-Quote conversion without splitting the journey into stacked
boards. Columns keep a useful fixed width and the board scrolls horizontally instead of compressing all five
to fit the viewport.

The default Assessment column is a presentation group over three protected Request states: Assessment
unscheduled, Assessment scheduled, and Assessment completed. Cards show the real state and, when scheduled,
the appointment date/time. **Settings → Pipeline → Show detailed assessment stages** expands Assessment into
those three columns, producing the seven-column detailed view. This setting changes presentation only; it
does not rewrite Request state, transitions, history, or reporting.

The seven underlying protected stages and their two record groups are:

**Requests** — New requests, Assessment unscheduled, Assessment scheduled, Assessment completed.  
**Quotes** — Draft, Awaiting response, Changes requested.

Each stage has one entry rule, and the rule is the whole definition:

| Stage | A card enters when |
| --- | --- |
| New requests | a new request is created |
| Assessment unscheduled | an assessment is required for the request but not scheduled yet |
| Assessment scheduled | an assessment for the request has been scheduled |
| Assessment completed | the assessment has been completed but not yet converted to a quote or a job |
| Draft | a new quote has been created but not sent to the client yet |
| Awaiting response | a quote has been sent and is awaiting approval or a change request |
| Changes requested | a quote has been sent and the client is requesting changes |

Parts 1 through 4 deliver the four Request stages. The Quotes campaign establishes Quote truth before the last
three are connected in Pipeline Part 5.

Dragging copies Jobber exactly when it arrives: forward only, and dropping into a protected stage opens or
performs the real required action, with the card moving only after that action succeeds. Backward dragging
cannot undo a business fact. Dragging and refused drops remain browser-only; they never ask the server to
write. A valid drop shows persistent saving feedback, keeps the card in its confirmed stage, and moves it only
after the server action and board refresh succeed. Part 1 ships without dragging, because only one group
exists, and cards must not look draggable until the behavior is real.

Elapsed time in the stage remains visible as neutral context, but age alone does not turn every card red.
Day-to-day priority comes from the next open Task: overdue first, due today next, no next Task after that, then
future Tasks. A separate inactivity warning uses an owner-configurable number of days for each stage. Expected
close date remains optional and is an alternate sort, not the default work queue. The protected-stage defaults
are New requests after 1 day, each Assessment state after 2 days, Draft after 2 days, Awaiting response after 5
days, and Changes requested after 2 days. The inactivity clock resets only for genuine progress: a customer
reply, a successful or externally confirmed send, a logged call that reached the customer (Connected or Left
voicemail), Task completion,
assessment scheduling/completion, Quote revision/send, or another protected domain action. Ownership, value,
and date edits; internal Notes; Task creation or reassignment; and manual custom-stage movement do not reset it.

Revision 3 adds section-bound custom follow-up stages under these rules:

- An organization may have up to 25 enabled custom stages. Names must be unique inside their Request or Quote
  section; the same name may exist once in each section.
- A custom stage belongs to either Requests or Quotes and cannot cross the conversion boundary.
- Protected stages cannot be renamed, reordered, hidden, disabled, or deleted.
- Custom stages organize follow-up only; they never replace or rewrite Request, Assessment, or Quote status.
- A real system action always moves the card to the protected stage that action establishes.
- Only owners and administrators configure stages through Settings; the board may link there.
- **Disable** is the normal removal action. Disabling a populated custom stage requires a destination in the
  same section and explicit reassignment of every open card. A stage that has ever been used remains as a
  historical identity and label; disabling it never rewrites prior events or reports.
- Manual movement among custom stages in the same section is allowed in either direction. Protected stages
  remain action-gated, and a real Request, Assessment, or Quote action always wins over custom placement.
- **On hold** is an ordinary custom follow-up stage, not an outcome. Any custom stage becomes an on-hold
  stage through its own switch in Settings, so an organization may name and keep several. Moving a card
  there requires a future Task — an open Task due after today; without one the board offers to add it and
  then completes the move. The card remains Open, its inactivity warning pauses only until that Task
  becomes due, and it never counts as Lost merely because it is on hold.
- One protected contractor pipeline is the launch model. Multiple independent pipelines, custom-stage
  automations, and administrator-built approval gates are not part of revision 3.

Money on cards and columns, ownership, and the filter and sort bar arrive with their own parts. Nothing shows a
placeholder value: a board without money shows no money rather than `$0.00`.

The board search covers client/contact name, title, Request or Quote number, service address, phone, and email.
It does not search Notes, file contents, or custom fields at launch. The board also supports lead-source
display/filtering, personal saved filters, administrator-shared saved filters, and an alternate table view.
Mobile defaults to a compact list. Lead source is a wider field-service pattern rather than documented current
Jobber Pipeline parity. Safe bulk tools cover only ownership, Tasks, and custom follow-up placement; customer
communication, conversion, protected-stage movement, and closing work are never silent bulk side effects.

## Outcomes

- Outcome is separate from stage: `open`, `won`, or `lost`.
- Won and Lost are not active-board columns.
- Archiving a never-sent Draft Quote removes it from the board as **Abandoned before sending**, retains its
  audit history, and creates no fake Lost event. It is excluded from Lost-reason and per-Quote win-rate math.
- Won is automatic when a Quote is approved or a Job is created. Staff do not manually mark a Request Won.
- A Request converted directly to a Job becomes Won once, and a Direct job appears as a separately labelled Won
  result. A Job made from an already-Won Quote never adds a duplicate result.
- Declining one Quote does not mark other Quotes in the same commercial thread Lost.
- A customer-declined sent Quote becomes Lost. The customer may leave an optional message, which is preserved;
  staff may then classify its internal Lost reason without forcing the customer to choose one.
- The customer's online quote offers Decline as a quieter choice beside Approve and Request changes (Housecall
  Pro; a frequent Jobber user request — Jafar, 2026-10-01). Declining asks "Mind telling us why?" with an
  optional pick — Too expensive, Went with someone else, No longer doing the work, Other — and an optional
  message. Their answer is kept as the customer's own words, separate from the staff Lost reason. The card
  becomes Lost as Customer declined and the quote's owner, or the office if none, gets an alert. Staff can
  still record a decline given by phone with "Mark as declined".
- Outside a customer's explicit decline, manually marking Lost is deliberate and archives the backing Request
  or Quote. A reason remains optional. Owners and administrators manage the reason list, initially: Price too
  high, Chose another contractor, No response, Project postponed, Work was not a fit, Duplicate or test request,
  and Other. Removing a reason retires it from future choices without rewriting old reports. A note is optional
  except that Other requires one.
- Reopening Lost is a deliberate UCRM addition because Jobber does not document that path. It requires a
  short explanation, restores the backing record and its prior valid open position, and records a new
  immutable outcome event.
- Won may be reopened only before a Job exists.
- Once a Job exists, Won is permanent.
- Closed Opportunities leave the active board and appear in the Won/Lost tiles and Sales Outcomes report.
  Reopening removes an Opportunity from the current Lost totals and results while preserving its Lost and
  Reopened events in immutable history.
- Sales reporting includes loss-reason breakdown, Request-to-Quote and Quote-to-Win conversion, source
  conversion, days to win, and time in stage. Outcome lists use the outcome date. Funnel reports group work by
  its created-date cohort and show still-Open work separately instead of misclassifying it. Request-to-Quote,
  Request-to-Won, and per-Quote win rates remain distinct. Direct jobs are shown separately and never inflate
  conversion percentages. Days to win shows both median and average; an absent duration or value remains
  missing rather than becoming a fake zero. Won value is frozen from the accepted Quote total, or from the Job
  total when a direct Request or Direct job becomes Won. Lost value is frozen from the last sent Quote total,
  or from the Opportunity value recorded on a Request when it becomes Lost. Later document edits never rewrite
  an earlier outcome value; missing values are labelled **Unvalued**.
- Conversion rates count work, not cards (Jafar, 2026-10-02). A Request and the Quote made from it are one
  piece of work and count once: Won if either was won, still Open if either is on the board, otherwise Lost
  if either was lost. Every rate divides by closed work only, so work still Open is never counted as lost.
  Work archived without being marked Lost is closed and counts as not won. A Draft Quote archived before
  anyone saw it is not a result, and a Direct job never enters a rate.

## Movement and automation

- Human movement into a protected stage must satisfy that stage's domain action.
- Backward dragging cannot undo completed business facts.
- Accidental forward movement needs a recovery path, but not a universal backward move. A safely reversible
  domain action may offer a short-lived Undo only while it remains the latest action and no later change has
  made reversal unsafe. An irreversible action requires confirmation before the drag commits. The card menu
  does not offer a permanent generic "Go back" action.
- Real Request, Assessment, and Quote activity may advance the card automatically.
- Automation never moves a card backward or overwrites later human progress.
- Repeated writes and provider/browser retries cannot duplicate transitions or history.
- Moving a Draft Quote to Awaiting response opens the real review surface: send by an available customer
  channel, deliberately mark it sent outside UCRM, view the Quote, or cancel. The card does not move until the
  chosen action succeeds; a drop alone never claims the customer received anything. Provider queue acceptance
  or a deliberate external mark-sent action establishes Awaiting response. An immediate send failure leaves
  the Quote in Draft. A later delivery failure does not rewrite the historical send, but remains visibly failed
  and alerts the responsible team member. Failed means the Quote's latest email bounced, was refused by the
  customer's mailbox or mail server, or was cancelled before it left; a spam complaint is not a failure. The
  card and Brief say "Delivery failed" until the Quote is sent again successfully. The one in-app alert goes
  to the card's owner, otherwise the sender, otherwise the account owner. External mark-sent records the actor, time, channel, and optional
  note. The channels offered are In person, Phone call, Text message, My own email, Printed or posted copy,
  and Other.
- Every card offers the same allowed destinations through a non-drag Move/next-action control. An unavailable
  destination says the exact reason and genuine next step; the generic “That card could not be moved” message
  is only a last-resort technical failure.

## Ownership and visibility

- An Opportunity may have one owner or remain unassigned.
- Opportunity details may include value and expected close date. Tasks are the only next-follow-up truth.
- Existing next-follow-up dates are migrated into open Tasks before the duplicate field is removed.
- Stage age is calculated from transition history using the organization's timezone where a calendar boundary
  matters.
- `sales.pipeline` package entitlement and Pipeline permissions are enforced on the server and through RLS-backed
  tenant isolation. Navigation visibility is only presentation.

## Opportunity Brief actions

- Selecting a card opens its Opportunity Brief without moving the user away from the board or losing the
  board's scroll, filters, or selected position.
- A Task is an internal follow-up item, not a Job, Visit, or Event. The Brief form has a required title and
  optional instructions, one owner, and one due date. Dated Tasks appear on the assignee's Schedule, and a new
  assignment or reassignment to someone else creates one in-app alert and one email. Phone and browser push,
  and per-teammate notification preferences, are a separate CRM-wide feature outside revision 3 (Jafar,
  2026-10-01). Self-assignment creates no alert, and the customer is never notified.
- Each Opportunity may have at most five open and five completed Tasks. The card shows one open Task: the
  earliest due one, breaking equal due dates by creation order; when none are due, it shows the oldest open
  Task. An overdue Task is visibly overdue. Completion and reopening happen from the Brief, not the card.
  A dated Task can also be ticked off or reopened from its box on the Schedule, with the same effect
  (Jobber's calendar does the same); a finished Task on a card that has left the board cannot be reopened.
- Task lifecycle follows Jobber: converting a Request to a Quote transfers its Tasks to the Quote; marking a
  Request Lost completes its Tasks; marking a Quote Lost or archiving its source removes its Tasks; Won does
  not carry Tasks into the Job: it completes the Tasks still open, so none is left on the Schedule or open
  where no screen shows it (Jafar, 2026-10-02; Jobber leaves this unstated). Reopening a Won Quote reopens
  only the Tasks that win completed. Reopening a Lost Request reopens only the Tasks that its matching Lost event
  completed automatically; Tasks a person completed remain completed. Parts 4 and 5 implement these
  transitions when those domain actions exist.
- Notes save immediately from the Brief and belong to either its backing Request/Quote or the Client, never to
  a second Pipeline-only copy. Staff may create, view, edit, delete, attach Files/photos, and mention a teammate;
  a mention notifies the tagged teammate.
- Quick actions expose Email, Text, and Call only when the Client has the required contact detail and the team
  member may use that channel. Messaging still obeys Communications consent, opt-out, allowance, and delivery
  rules; a quick action is not a second sending system. Email and Text open the existing Communications
  composer, which writes to the Client's primary address or number. Call opens the device dialler, and several
  phone numbers open a chooser. Opening the dialler never pretends that a call connected or records an
  automatic call outcome.
- Calls are logged by a person (Jafar, 2026-10-02, after comparing HubSpot, Pipedrive, GoHighLevel, Jobber and
  Housecall Pro). Tapping Call, or "Log call", opens a bar asking how it went, with five outcomes and no default:
  Connected, Left voicemail, No answer, Busy, Wrong number, plus an optional note. Only Connected and Left
  voicemail restart the inactivity clock, because only they reached the customer; the other three are kept in
  the card's call history without restarting it. After No answer or Busy the bar offers a one-tap "Try again
  tomorrow" Task for the caller. The history shows on the Brief; the Client record does not show it yet.
- `pipeline.view` permits reading Brief Tasks and Notes. `pipeline.edit` is required to create, edit,
  complete, reopen, move, or delete them. Opportunity ownership does not grant extra mutation authority.
- Brief Notes are authorized by `pipeline.edit` through a Pipeline-scoped path, separate from the generic
  Notes surface's `customers.edit`/`property.manage` gate used by the Request and Client detail pages. Both
  paths write the same underlying `notes`/`note_links` rows, so a Client-targeted Brief Note also appears on
  that Client's own Notes card; a Request-targeted one appears only on that Request's. A staff member with
  `pipeline.edit` but not `customers.edit` can still manage Notes from the Brief.
- The first-release Brief has no embedded activity timeline. Request history remains available on the Request
  record; a trustworthy merged Opportunity timeline is separately deferred.

## Platform

The Pipeline website works on phones before a native app exists. Mobile shows a focused stage or compact list
instead of shrinking the desktop board, and uses tap-based Move/next-action controls so dragging is never
required. A future native app may share these business rules but has its own interface requirements.

The page owns vertical scrolling and the board owns one horizontal scroll for its fixed-width columns. Each
column offers an accessible `Load more` control for its next page. Independent lane scrolling or automatic
loading is adopted only after a live usability prototype and measured-load check prove it better.

## Boundaries

- Jobs, Visits, Invoices, and Payments do not continue through the sales Pipeline.
- Jobs do not become active-board cards. The Jobs campaign owns Job creation and behavior; Pipeline only records
  the resulting Won outcome, including a separately labelled closed-only Direct job.
- Quote pricing, approval, versioning, signature, and conversion belong to Quotes.
- Conversations belong to Communications; Pipeline may show linked context after that domain exists.
- AI summaries and weighted-probability forecasting remain optional post-launch work. Pipeline value and
  Expected close date remain available without pretending a win probability is known.
- Multiple independent pipelines, custom-stage automations, administrator-built approval gates, note pinning,
  repeating Tasks, the embedded Opportunity timeline, and phone/browser push with per-teammate notification
  preferences are outside revision 3. Immutable stage/outcome
  history remains required for reporting even though that history is not yet rendered in the Brief.
- The board never creates work. Any global create control on the page belongs to Requests or Quotes, not to
  the Pipeline.

## Still unclear

None for revision 3. Jafar approved the corrected foundation, detail rules, and final industry-backed edge
cases on 2026-10-01.

## Not doing

The items explicitly outside revision 3 are listed under **Boundaries**. They include multiple independent
pipelines, custom-stage automations, administrator-built approval gates, AI summaries, weighted-probability
forecasting, note pinning, repeating Tasks, and an embedded Opportunity timeline. These may be reconsidered by
a later approved plan; the revision 3 build does not silently include them.

Two more wait on work outside the Pipeline and are recorded in `Memory/deferred/` so they are built before
launch: phone/browser push with per-teammate notification preferences (UCRM has no push system yet; Task and
mention alerts use the in-app alert and email until it exists), and sending a Quote by text from the send
window (Quotes can only be emailed until the Quotes area can text one).
