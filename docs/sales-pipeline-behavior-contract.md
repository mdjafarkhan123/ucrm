# Sales Pipeline behavior contract

Status: Approved 2026-08-18. Revised 2026-08-24 for the unified board and stage customization model.
Owner: Sales Pipeline campaign

## Purpose

The Pipeline helps contractors see and advance open commercial work from Request through Quote. It is a sales
view, not a replacement status machine and not an operational Job board.

Industry evidence and deliberate differences are recorded in
`docs/research/contractor-crm-sales-pipeline-comparison.md`.

## Opportunity identity

Jobber's current behavior is the reference. Where the earlier UCRM opportunity model disagreed with it, Jobber
wins.

- Opportunities are only ever generated from real work. Staff never create one by hand, and there is no
  standalone Opportunity.
- Every Request automatically has exactly one Opportunity, created with the Request.
- Every Quote will automatically have exactly one Opportunity, created with the Quote in Part 5.
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

Stage age is measured from `stage_entered_at`, and follows Jobber's freshness rule: green under one hour,
neutral from one to 24 hours, red after 24 hours.

Arbitrary custom stages are not part of this release. A later release may add section-bound custom follow-up
stages under these rules:

- A custom stage belongs to either Requests or Quotes and cannot cross the conversion boundary.
- Protected stages cannot be renamed, reordered, hidden, disabled, or deleted.
- Custom stages organize follow-up only; they never replace or rewrite Request, Assessment, or Quote status.
- A real system action always moves the card to the protected stage that action establishes.
- Only owners and administrators configure stages through Settings; the board may link there.
- Disabling or removing a populated custom stage requires a destination in the same section and explicit bulk
  reassignment. Automation dependencies must be resolved first, and historical stage events retain their
  original identity and label.

Money on cards and columns, ownership, and the filter and sort bar arrive with their own parts. Nothing shows a
placeholder value: a board without money shows no money rather than `$0.00`.

Lead source appears inconsistently across Jobber's own screens and documentation, so it is not a first-release
requirement.

## Outcomes

- Outcome is separate from stage: `open`, `won`, or `lost`.
- Won and Lost are not active-board columns.
- Won is automatic when a Quote is approved or a Job is created. Staff do not manually mark a Request Won.
- Declining one Quote does not mark other Quotes in the same commercial thread Lost.
- Marking Lost is deliberate and archives the backing Request or Quote. A reason is optional, matching
  Jobber. When supplied, it is one of: Price too high, Chose another contractor, No response, Project
  postponed, Work was not a fit, Duplicate or test request, or Other. A note is optional except that Other
  requires one.
- Reopening Lost is a deliberate UCRM addition because Jobber does not document that path. It requires a
  short explanation, restores the backing record and its prior valid open position, and records a new
  immutable outcome event.
- Won may be reopened only before a Job exists.
- Once a Job exists, Won is permanent.
- Closed Opportunities leave the active board and appear in the Won/Lost tiles and Sales Outcomes report.
  Reopening removes an Opportunity from the current Lost totals and results while preserving its Lost and
  Reopened events in immutable history.

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

## Ownership and visibility

- An Opportunity may have one owner or remain unassigned.
- Opportunity details may include value, expected close date, and next follow-up.
- Stage age is calculated from transition history using the organization's timezone where a calendar boundary
  matters.
- `sales.pipeline` package entitlement and Pipeline permissions are enforced on the server and through RLS-backed
  tenant isolation. Navigation visibility is only presentation.

## Opportunity Brief actions

- Selecting a card opens its Opportunity Brief without moving the user away from the board or losing the
  board's scroll, filters, or selected position.
- A Task is an internal follow-up item, not a Job, Visit, or Event. The first Brief form has a required title
  and optional instructions, one owner, and one due date. Repeating tasks, timed scheduling, reminders, and
  the Schedule UI arrive with the Schedule domain, but the Task foundation must remain reusable there.
- Each Opportunity may have at most five open and five completed Tasks. The card shows one open Task: the
  earliest due one, breaking equal due dates by creation order; when none are due, it shows the oldest open
  Task. An overdue Task is visibly overdue. Completion and reopening happen from the Brief, not the card.
- Task lifecycle follows Jobber: converting a Request to a Quote transfers its Tasks to the Quote; marking a
  Request Lost completes its Tasks; marking a Quote Lost or archiving its source removes its Tasks; Won does
  not carry Tasks into the Job. Reopening a Lost Request reopens only the Tasks that its matching Lost event
  completed automatically; Tasks a person completed remain completed. Parts 4 and 5 implement these
  transitions when those domain actions exist.
- Notes save immediately from the Brief and belong to either its backing Request or the Client, never to a
  second Pipeline-only copy. Staff may create, view, edit, and delete them in the first release.
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

The Pipeline is a desktop web experience. A separate mobile app will be built later and carries its own
requirements, so this campaign has no mobile UI and no mobile acceptance checks. Jobber's own app has no
pipeline either.

The page owns vertical scrolling and the board owns one horizontal scroll for its fixed-width columns. Each
column offers an accessible `Load more` control for its next page; automatic loading may enhance that later.

## Boundaries

- Jobs, Visits, Invoices, and Payments do not continue through the sales Pipeline.
- A Job relationship only makes Won terminal; the Jobs campaign owns Job creation and behavior.
- Quote pricing, approval, versioning, signature, and conversion belong to Quotes.
- Conversations belong to Communications; Pipeline may show linked context after that domain exists.
- Custom stages, AI summaries, automations, forecasting, the embedded activity timeline, note attachments,
  note mentions, note pinning, repeating Tasks, Task notifications, and Task Schedule UI are outside the
  first release.
- The board never creates work. Any global create control on the page belongs to Requests or Quotes, not to
  the Pipeline.
