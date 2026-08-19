# Part 3: Actionable Opportunity Brief with Tasks and Notes

Status: Closed 2026-08-19. 3A, 3B, and 3C all closed 2026-08-19.

## Outcome

Staff can manage accountable follow-up and deal context from the Opportunity Brief without leaving or losing
their place on the Pipeline board. The thin Part 1 drawer grows in place. The permanent product behavior lives
in `docs/sales-pipeline-behavior-contract.md`; this packet owns execution order and acceptance.

## Approved scope

- Build a reusable Task foundation, then its Opportunity Brief/card UI, then immediate-save Notes.
- A Brief Task has a required title and optional instructions, one owner, and one due date. It is an internal
  to-do, not a Job, Visit, or Event.
- Follow Jobber's five-open and five-completed limits and its card-priority rule.
- Follow Jobber's later lifecycle behavior: Request-to-Quote transfers Tasks; Lost Request completes them;
  Lost Quote or archive removes them; Won does not carry them into the Job. Parts 4/5 own those integrations.
- `pipeline.view` reads Tasks and Notes. `pipeline.edit` gates every mutation, regardless of ownership.
- Brief Notes link to the backing Request or Client and support create, view, edit, and delete.
- The embedded activity timeline, attachments, mentions, pinning, repeating Tasks, Task notifications, timed
  scheduling, and Schedule UI are outside Part 3.
- Desktop web only. Preserve the board behind the drawer and all URL/filter/scroll state.

## Dependencies and existing seams

- Parts 1 and 2 are closed; preserve their dirty working-tree implementation.
- `OpportunityBriefDrawer.svelte` grows in place. `SidePanel.svelte` already owns the drawer shell.
- `fetchAssignableTeam` and `assignableTeamKey` are the one eligible-owner source.
- Notes already use `notes`, `note_links`, `/api/notes`, `$lib/collaboration/api.ts`, and collaboration UI.
- Current Note creation performs the Note insert and link insert separately; Part 3C must make that atomic.
- No Task schema, API, or UI exists. No Schedule route exists. Part 3A must establish the correct seam without
  building a Pipeline-only dead end or a placeholder Schedule.
- Existing generic activity is incomplete and remains outside this part.

## Checklist

### 3A. Reusable Task foundation — closed 2026-08-19

Shipped: `public.tasks` (one Opportunity column, not a Pipeline-only table, so Schedule reads the same rows
and Part 5 moves a Task by repointing one column), the five-open/five-completed limits enforced under a lock
on the parent Opportunity, an assignee check matching Opportunity ownership, three partial indexes, one
select-only grant with no write policy, four security-definer write functions, Zod schemas, and the
`/api/pipeline/opportunities/[id]/tasks` and `/api/pipeline/tasks/[taskId]` routes.

Migrations: `20260819053723_task_foundation.sql`,
`20260819054026_task_rls_permission_lookup_once_per_query.sql`.

Verified remotely in rolled-back transactions: create/edit/complete/reopen/delete, an already-completed
retry changing nothing, both limits, invalid assignee, cross-tenant refusal, unknown-id refusal, view-only
members reading but never writing, direct table writes refused, and index-only plans for both Brief reads.

#### 3A completion gate

The reusable Task foundation is tenant-isolated, permission-safe, concurrency-safe, bounded, indexed, and
remotely verified. No Brief/card or Schedule UI has been started. Stop and hand off to 3B.

### 3B. Task Brief and card UI — closed 2026-08-19

Shipped: `OpportunityTasksSection.svelte` (open/completed lists, five-open count pill, complete/reopen
checkbox, row `Edit`/`Delete` menu) and `TaskDialog.svelte` (shared create/edit form) in the Brief;
`opportunityTasksKey`/`fetchOpportunityTasks`/`createTask`/`updateTask`/`setTaskCompletion`/`deleteTask`/
`TaskWriteError` in `$lib/pipeline/api.ts`, nested under `['pipeline']` so `invalidatePipeline` refreshes
both the Brief list and the board in one call. `OpportunityCard.svelte` shows the one open Task with overdue
styling. `pipeline_board_page` (migration `20260819060000_pipeline_board_page_open_task.sql`) now returns
each card's earliest-open Task via a `LEFT JOIN LATERAL` against `tasks_opportunity_open_idx` — same index
the Brief's own list reads, confirmed in use (not flagged unused) by the advisors.

Verified: 103 pipeline tests + 564 full-suite tests pass; `npm run check` clean. Browser-verified live:
create with owner + overdue due date, card shows the task with "Overdue", complete removes it from the card,
reopen restores it, edit updates both Brief and card, delete via `ConfirmDialog` removes it and restores
"No tasks yet" — board scroll/filters/other cards untouched throughout.

#### 3B completion gate

Staff can create, edit, complete, reopen, and delete permitted Tasks from the Brief; the correct open Task is
shown on the card; the board never loses the user's place. Stop and hand off to 3C.

### 3C. Immediate-save Notes — closed 2026-08-19

Shipped: generic `create_note` DB function (atomic note+link insert, fixes the pre-existing orphaned-note
bug) and a **separate Pipeline-scoped Notes path** — `private.pipeline_note_scope` +
`pipeline_opportunity_notes` / `pipeline_create_opportunity_note` / `pipeline_update_opportunity_note` /
`pipeline_delete_opportunity_note`, all security-definer, authorized by pipeline.view/pipeline.edit (not
customers.edit), resolving Request/Client ids from the Opportunity row itself. Migrations:
`20260819070000_notes_atomic_create.sql`, `20260819071500_pipeline_scoped_opportunity_notes.sql`, both
applied and remote-verified in rolled-back transactions (pipeline.edit-only member writes a Client note;
direct table write still refused by generic RLS; cross-opportunity and cross-tenant refusal; atomicity).
API: `src/routes/api/notes/+server.ts` POST now uses `create_note`; new
`src/routes/api/pipeline/opportunities/[id]/notes/+server.ts` (GET/POST) and `.../[noteId]/+server.ts`
(PATCH/DELETE); helpers in `$lib/server/pipeline/notes.ts`, schemas in `pipeline.schema.ts`
(`pipelineNoteCreateSchema`/`pipelineNoteUpdateSchema`/`pipelineNoteEntityTypeSchema`). Client:
`$lib/pipeline/api.ts` adds `PipelineNote`, `opportunityNotesKey`, fetch/create/update/delete — its own
query key, never triggers `invalidatePipeline`. Component: `OpportunityNotesSection.svelte`
(immediate-save, Request/Client `SegmentedControl` target picker, badge per note, reuses
`AuthorMeta`/`Textarea`/`ConfirmDialog`/`EmptyState`), wired into `OpportunityBriefDrawer.svelte` after
Tasks. Tests: `src/routes/api/notes/notes.spec.ts`,
`src/routes/api/pipeline/opportunities/[id]/notes/notes.spec.ts` + `[noteId]/note.spec.ts`,
`OpportunityNotesSection.svelte.spec.ts` — full suite 593/593 passing, `npm run check` clean.

Browser-verified live: Request-target and Client-target note creation from the Brief; both list with
correct badges; edit opens correctly; the Client-targeted note appears on the Client detail page's own
Notes card (same row, correctly scoped — the Request one correctly does NOT appear there).

- [x] Browser-verified: edit save updates the note in place (shows "edited"); delete through `ConfirmDialog`
  removes the note after confirming the dialog copy; a Request-targeted note appears on that Request detail
  page's own Notes card, scoped correctly (2026-08-19, "A test request").

#### 3C completion gate

Staff can manage core deal Notes from the Brief without orphaned rows, permission leaks, stale drawer state,
or leaving the board.

## Part completion gate

The Brief provides Jobber-style Tasks and core Notes end to end; database/API/component/browser/accessibility/
performance checks pass; lifecycle hooks needed by Parts 4/5 are explicit and testable; deferred activity and
Schedule work are not represented as shipped.

## Non-discoverable risks

- The working tree contains extensive uncommitted Part 2 work overlapping Pipeline UI, API, validation, and
  Memory. Preserve it and layer changes narrowly; never reset or replace those files wholesale.
- A selected Opportunity in the Brief is a click-time snapshot. Cache invalidation refreshes the board behind
  it but does not update the open drawer; visible mutations need the established local patch path.
- Enforcing the Task cap only in an API count-then-insert race is unsafe. The database owns the invariant.
- A Task foundation tied only to a Pipeline card will be the wrong seam when Schedule arrives. Reusability
  means a real Task domain, not implementing Schedule fields or UI early.
- Jobber's Lost/archive behavior is destructive in the product surface. Preserve only the minimum internal
  audit evidence required by UCRM security while matching the approved visible behavior.
- Do not leak estimated-value amounts into generic Task/Note/activity payloads for users lacking
  `pipeline.view_value`.

## Sources

- `docs/sales-pipeline-behavior-contract.md`
- `CONTEXT.md`
- `.claude/skills/jobber/jobber-02-requests-leads.md` §4.6.1–4.6.2
- Current official Jobber Sales Pipeline: https://help.getjobber.com/en/articles/sales-pipeline/
- `src/lib/server/access/permission.ts`, `src/lib/server/security/rate-limit.ts`
- `src/lib/server/validation/`, `src/routes/api/pipeline/`, `src/lib/pipeline/`
- `src/lib/collaboration/api.ts`, `src/routes/api/notes/`, `src/lib/components/collaboration/`
- `src/lib/team/api.ts`, `src/lib/components/layout/SidePanel.svelte`
