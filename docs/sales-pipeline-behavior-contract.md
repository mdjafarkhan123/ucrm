# Sales Pipeline behavior contract

Status: Approved 2026-08-18. Revised 2026-08-18 to follow Jobber's current Sales Pipeline.  
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

The board copies Jobber's seven protected stages, in two groups:

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
cannot undo a business fact. Part 1 ships without dragging, because only one group exists, and cards must not
look draggable until the behavior is real.

Stage age is measured from `stage_entered_at`, and follows Jobber's freshness rule: green under one hour,
neutral from one to 24 hours, red after 24 hours.

Custom stage creation, renaming, deletion, and reordering are later enhancements. Add them only after real user
evidence justifies the complexity.

Money on cards and columns, ownership, and the filter and sort bar arrive with their own parts. Nothing shows a
placeholder value: a board without money shows no money rather than `$0.00`.

Lead source appears inconsistently across Jobber's own screens and documentation, so it is not a first-release
requirement.

## Outcomes

- Outcome is separate from stage: `open`, `won`, or `lost`.
- Won and Lost are not active-board columns.
- Approving a Quote automatically marks that Quote's Opportunity Won.
- Declining one Quote does not mark other Quotes in the same commercial thread Lost.
- Marking Lost is deliberate and requires a structured reason; an optional note may add context.
- Reopening Lost requires a reason and restores the prior valid open position.
- Won may be reopened only before a Job exists.
- Once a Job exists, Won is permanent.
- Closed Opportunities leave the active board but remain in outcome history and reporting.

## Movement and automation

- Human movement into a protected stage must satisfy that stage's domain action.
- Backward dragging cannot undo completed business facts.
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

## Platform

The Pipeline is a desktop web experience. A separate mobile app will be built later and carries its own
requirements, so this campaign has no mobile UI and no mobile acceptance checks. Jobber's own app has no
pipeline either.

The board scrolls once, at page level. Each column offers an accessible `Load more` control for its next page;
automatic loading may enhance that later.

## Boundaries

- Jobs, Visits, Invoices, and Payments do not continue through the sales Pipeline.
- A Job relationship only makes Won terminal; the Jobs campaign owns Job creation and behavior.
- Quote pricing, approval, versioning, signature, and conversion belong to Quotes.
- Conversations belong to Communications; Pipeline may show linked context after that domain exists.
- Custom stages, AI summaries, automations, tasks, notes, and forecasting are outside the first release.
- The board never creates work. Any global create control on the page belongs to Requests or Quotes, not to
  the Pipeline.
