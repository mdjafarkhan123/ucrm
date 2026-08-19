# Part 4: Won, Lost, Reopen, and Sales Outcomes

Status: Closed 2026-08-19. All three subparts (4A, 4B, 4C) shipped and verified.

## Outcome

Close Request Opportunities without weakening Request truth: Jobber-style Lost archives the Request and
completes its open Tasks; UCRM's reasoned reopen restores both safely. Closed Opportunities leave the active
board and feed current Won/Lost totals and a Sales Outcomes report while immutable events preserve every
transition. Automatic Won is prepared for Quote/Job callers without exposing a manual Request action.

Authoritative behavior: `docs/sales-pipeline-behavior-contract.md` "Outcomes" and "Opportunity Brief
actions". Jobber evidence: `.claude/skills/jobber/jobber-02-requests-leads.md` §4.6.1–4.6.2.

## Approved behavior

- Copy Jobber where documented: automatic Won on Quote approval or Job creation; manual Lost; archive the
  backing Request/Quote; optional lost reason; closed cards leave the board; current outcomes remain in the
  tiles/report. A Request has no manual Won action.
- First-release lost reasons are Price too high, Chose another contractor, No response, Project postponed,
  Work was not a fit, Duplicate or test request, and Other. Leaving the reason unselected is valid. Other
  requires a note; every other note is optional.
- Reopen is an UCRM addition. It is available from a Lost row in Sales Outcomes, requires a short explanation,
  restores the Request to its prior valid open position, and reopens only Tasks completed automatically by
  that matching Lost event. Human-completed Tasks remain completed.
- A reopened Opportunity is active, so it leaves current Lost tiles/results. Its Lost and Reopened events
  remain immutable. Losing it again creates a new event rather than rewriting the first cycle.
- Notes remain on their Request or Client and are never removed by an outcome transition.
- Won reopen remains governed by the behavior contract, but no Won caller or UI is fabricated before Quotes
  and Jobs provide the real facts.

## Dependencies and boundaries

- Parts 1–3 are closed. Preserve their URL-derived board state, query keys, value permission, Brief, Tasks,
  Notes, owner eligibility, and single Opportunity write path.
- Part 4 may extend `opportunities`, Task completion provenance, read functions, indexes, RLS, grants, API
  validation, Pipeline UI, and campaign-owned tests.
- It creates no Quote, Job, Schedule, activity-timeline, automation, notification, or custom-stage behavior.
- `pipeline.view` reads current outcomes. `pipeline.edit` performs Lost/Reopen. `pipeline.view_value` alone
  permits monetary totals or row values. Opportunity ownership grants no mutation authority.
- Confirmed schema/RLS scope is limited to this approved packet. Use the imperative migration workflow and
  preserve all uncommitted Part 1–3 work.

## 4A: Atomic outcome engine — closed 2026-08-19

Completion gate: Lost/Reopen and the future automatic-Won seam are transactionally correct and database-
verified before any UI calls them. Met: migration `20260819080000_pipeline_outcome_engine.sql`, pgTAP suite
`supabase/tests/database/pipeline_outcome_engine.sql` (49/49 passing against the dev project).

- [x] Add the smallest current-outcome fields and immutable `opportunity_outcome_events` shape needed for
  current reporting, stable audit, actors, timestamps, optional lost reason/note, required reopen explanation,
  source/restoration facts, Task provenance, and per-command idempotency.
- [x] Add tenant-safe foreign keys, checks, RLS, grants, and indexes for current outcome/date paging and event
  history. Keep authenticated members unable to write Opportunity outcome columns or event rows directly.
- [x] Add narrow Lost and Reopen database commands. Keep the shared transition engine private so browser/API
  callers cannot manufacture Won. Reserve automatic Won for future Quote/Job domain callers.
- [x] In one short transaction, lock in a consistent order; verify organization, permission, current outcome,
  and eligible non-converted Request; archive/restore the Request; change only Tasks tied to that outcome
  event; update current outcome; and append exactly one immutable event.
- [x] Make same-key retries return the original result. Reject stale or conflicting commands without partial
  source, Task, Opportunity, or history changes.
- [x] Database-test tenant isolation, missing permissions, direct-write refusal, valid transitions, terminal
  converted Requests, duplicate retries, concurrent Lost/Reopen attempts, rollback, Other-without-note,
  optional reasons, Task provenance, five-Task limits after reopen, and index-backed report access.

**Found and closed during 4A, approved by Jafar:** the Request detail page's plain `Archive`/`Bring back`
menu item wrote `requests.status` straight to `archived`/`new` through `PATCH /api/requests/[id]`, with no
`pipeline.edit` check, no reason, no outcome event, and no Task completion — a silent bypass of the outcome
model, since every Request already has an Opportunity. Closed at the database layer: a guard trigger
(`private.request_reject_direct_archive_transition`) refuses any `archived`-involving status write unless
the calling function first flags that exact request id via a transaction-local `set_config`, which only
`pipeline_mark_opportunity_lost`/`pipeline_reopen_opportunity` do. The generic PATCH route's Zod schema now
rejects `status: 'archived'` outright, and the menu item was removed from the Request detail page. **4B's
`Mark as lost` card action and Sales Outcomes `Reopen` control are now the only way a Request is archived or
restored** — there is no other UI for it until 4B ships.

## 4B: Lost and Reopen actions — closed 2026-08-19

Completion gate: permitted staff can close a Request Opportunity from the card menu with clear consequences,
resilient retries, and correct cache updates; the Reopen database action exists and is route-tested, but its
user-facing entry point is deliberately deferred to 4C. Met.

- [x] Zod schemas (`markOpportunityLostSchema`, `reopenOpportunitySchema`) and `POST /api/pipeline/
  opportunities/[id]/lost` / `.../reopen`, calling `pipeline_mark_opportunity_lost` / `pipeline_reopen_opportunity`
  directly. UUID idempotency keys, fixed reason vocabulary, Other-requires-note, reopen explanation all
  validated before the database is asked.
- [x] `Mark as lost` added to a new `OpportunityCard` `...` menu (Jobber has `Salesperson` there too, but that
  is already the card's direct owner control from Part 2 — no duplicate menu entry for it).
  `MarkOpportunityLostDialog.svelte` (Dialog + Select + Textarea, mirrors `TaskDialog`) states the Request
  leaves the board, is archived, and has its open Tasks completed.
- [x] Card stays in place and the dialog stays actionable on failure (browser-verified: a 500 leaves the
  button enabled and the message visible). Success invalidates the `['pipeline']` query family the same way
  the owner-assign mutation does.
- [x] Reopen ships as `POST /api/pipeline/opportunities/[id]/reopen` + `reopen.spec.ts` only. No Reopen UI
  entry point anywhere in 4B, confirmed with Jafar 2026-08-19.
- [x] `lost.spec.ts` / `reopen.spec.ts` (auth, permission, validation, error-code mapping, retried-command
  passthrough, cache headers) and `MarkOpportunityLostDialog.svelte.spec.ts` (Other/note gating, form-error
  display, failure leaves the dialog actionable). 114/114 pipeline tests pass; browser-verified end to end —
  Lost archived the real Request (confirmed on the Requests list) and removed the card from its column.

**Found during 4B, not a blocker:** `OpportunityCard` also got an `onLost` callback, threaded through
`PipelineColumn` to `+page.svelte`, to close the open Brief if the card just marked lost is the one
currently selected. Browser-testing it revealed `SidePanel` (`src/lib/components/layout/SidePanel.svelte`)
is a true Bits UI modal — full-page overlay, focus-trapped — not a non-modal side drawer, so the board
behind an open Brief is not clickable at all. The scenario this wiring exists for (open a Brief, then use
the same or a different card's `...` menu behind it) cannot happen through the UI as built today. The
wiring is left in place because it is cheap, correct, and matches the packet's approved requirement, but it
is currently inert. Worth remembering for any future work that assumes the board stays interactive behind
an open Brief — it does not.

## 4C: Current Sales Outcomes — closed 2026-08-19

Completion gate: the Pipeline tiles and paged report agree on current closed work, reopened work disappears,
and money never crosses the existing value permission. Met.

- [x] `pipeline_outcome_tiles` (fixed rolling 30 days, org timezone, `resolveDateRange`) backs Won/Lost tiles
  above the board with current counts and permitted value totals, at `GET /api/pipeline/outcomes/summary`.
- [x] Tiles link to `/pipeline/outcomes?type=won|lost&date=last_30_days`. No Insights/Reports hub added.
- [x] `/pipeline/outcomes` built on `pipeline_outcome_page`, Type/date filters, sortable Title/Client/Created
  At/Outcome date/Total columns, keyset paging (two-phase for Total's nullable estimate, mirroring the board's
  own value-sort split), Reopen action on Lost rows only. Direct-URL default is `type=won` (Jobber parity, not
  designed around the temporary lack of a Won caller — approved by Jafar 2026-08-19). Lost-reason reporting
  intentionally not added; the stored reasons remain for a later slice.
- [x] `estimated_value` and the Total/Client sort options are absent entirely without `pipeline.view_value` /
  `customers.view`, both in the database function and the route (mirrors `pipeline_board_page`'s value-sort
  refusal). Never a masked or zero value.
- [x] Tiles/report query keys live under `['pipeline']`, so the existing `invalidatePipeline()` call in
  `MarkOpportunityLostDialog`/`ReopenOpportunityDialog` already reaches them — no new invalidation path needed.
  Browser-verified: reopening removed the row from the Lost report and its tile count in the same round trip.
- [x] Migration + two new API routes unit-tested (`outcomes-report.spec.ts` cursor round trips,
  `summary.spec.ts`, `outcomes.spec.ts` — permission, sort refusal, cursor validation, masking, paging).
  `ReopenOpportunityDialog.svelte.spec.ts` covers the disabled-until-typed/failure-recovery behavior the same
  way `MarkOpportunityLostDialog`'s does. Browser-verified: Won empty state, Lost report with real data
  (Mark as lost → appears in report and tile with correct total), sort-by-Title, back-button restoring the
  prior sort, dark theme, and a full Lost → Reopen → back-on-board round trip.
- [x] Performance: measured with `EXPLAIN (ANALYZE, BUFFERS)` against 50,000 closed opportunities seeded in a
  throwaway organization (deleted after). Created/Outcome date/Total sorts are index-backed, page-1 and a deep
  page (offset 25,000) cost the same (~0.2-0.4ms). Title/Client sorts do a Seq Scan + top-N heapsort by design
  (Jafar declined a speculative index) — flat ~30-50ms per page regardless of depth at 50k rows, under the
  performance-review skill's 100ms guideline. No index added; re-measure if any org's closed-opportunity count
  reaches an order of magnitude higher.

## Non-discoverable risks

- `opportunities.outcome` exists, but authenticated writes were deliberately removed in Part 2. Preserve that
  boundary; exposing a generic outcome update would silently create manual Won.
- Request status and Pipeline stage are source-derived. Reopen must restore the saved valid Request state and
  let the existing stage trigger recompute; application code never writes `stage` or `stage_entered_at`.
- Completing every open Task on Lost loses which ones a person completed. Record the loss event on only the
  Tasks changed by that transition so Reopen can reverse exactly those rows.
- Current reporting and immutable audit answer different questions. Tiles/report use current closed state;
  outcome events retain prior Lost/Reopened cycles and must not be rewritten to make current totals easy.
- Outcome totals are a financial read even when returned only as an aggregate. Reuse the existing two-layer
  `pipeline.view_value` enforcement and measured paging/index patterns.
- The existing working tree contains approved, uncommitted Part 1–3 work. New migrations are additive; never
  rewrite, squash, or discard it.

## Part 4 completion gate — met 2026-08-19

Part 4 closes only when all three subparts pass their gates and database/API/component/browser verification
proves atomic, permission-safe, idempotent Lost/Reopen behavior; exact Task restoration; current outcome
reporting; value isolation; stable Request/Assessment/Notes behavior; and preserved immutable history. All
three subparts (4A, 4B, 4C) closed 2026-08-19; see each subpart above for what verified it.
