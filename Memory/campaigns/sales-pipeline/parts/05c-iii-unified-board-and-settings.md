# Part 5C-iii: Unified board and Pipeline presentation setting

## Scope

Turn the two stacked column groups into one horizontal journey with five visible columns by default, add
the owner/admin Settings toggle that expands Assessment into its three protected stages, and keep every
default-view action that the current seven-column board already supports. Arbitrary custom stages stay out.

## Approved decisions (Jafar, 2026-08-24)

1. **Groups stay.** One board, two labelled groups with their own icons and totals, laid out horizontally.
   Requests spans New requests + Assessment. Quotes spans Draft + Awaiting response + Changes requested.
   A clear vertical boundary sits before Draft.
2. **No arbitrary stage lists in the API.** The opportunities route accepts a named logical column
   (`assessment`) that the server maps to the three approved assessment stages. Ordinary columns keep their
   real stage values. The cursor is bound to the logical column so it cannot be replayed against another.
3. **The grouped read returns the appointment.** Request status alone is not enough for the contract's
   "cards show the real state and, when scheduled, the appointment date/time". The grouped read adds the
   assessment's scheduled instant, and keeps one globally correct keyset order across all three states.
4. **The collapsed view stays actionable.** The Brief offers the real next action for the card's sub-state:
   unscheduled → Schedule assessment; scheduled → Mark assessment complete; completed → Create quote. The
   card shows a state badge and the appointment date only — no extra buttons per card.
5. **Request-to-Draft is a designed boundary, not a side effect.** See "Conversion boundary" below.
6. **The toggle lives in `organization_settings`,** written through the existing Settings pattern:
   owner/admin authorization, Zod validation, revision conflict check, editor stamp, audit row, explicit Save.
7. **The preference reaches the board through the Pipeline summary query,** which already runs at
   `staleTime: 30_000` and is already reached by `invalidatePipeline`. No new refresh claim is invented.
8. **Indexes and query plan are decided before the migration,** and multi-stage keyset pagination gets
   representative tests.

## Dependencies

5C-ii (closed). Quotes Parts 1-6 (closed) for `convert_request_to_quote`. Contractor-settings' existing
`organization_settings` revision/audit pattern.

## Conversion boundary (decision 5)

Dropping a Request card onto **Draft** converts it. The real command already exists:
`public.convert_request_to_quote(target_request_id, idempotency_key, request_hash)`
(`supabase/migrations/20260820002553_quotes_request_conversion.sql`), reached today through
`POST /api/requests/[id]/convert-to-quote`.

- **Convertible statuses are `new`, `unscheduled`, `assessment_completed`** — the allow-list the database
  itself enforces and `src/routes/(app)/requests/[id]/+page.svelte:325` mirrors. This covers both required
  paths: New requests → Draft (direct quote, no assessment) and Assessment completed → Draft.
- **A scheduled assessment is not convertible.** The collapsed Assessment column therefore holds a mix of
  convertible and non-convertible cards, so the Draft drop target is decided **per card, not per column**.
  `dropRefused` in `PipelineColumn.svelte` currently answers per column and must learn the card-level case.
  A card that cannot convert does not light Draft up during its own drag.
- **The card stays put until the Quote exists.** Same server-confirmed pattern 5C-ii already ships: source
  column keeps the card, loading toast, `invalidatePipeline`, then the Request card disappears and the new
  Quote card appears in Draft. Cancel or failure changes nothing.
- **Conversion is confirmed, never silent.** It is irreversible in the 5D sense (a Quote now exists and the
  Request is `converted`, which is terminal). The drop opens a confirmation naming the client and the
  request, with Convert primary and Cancel secondary. No Undo is offered for it.
- **No navigation on success.** The person stays on the board; the toast names the new quote number. The
  Request page's existing convert flow is untouched.
- **5D coordination:** conversion is recorded in this packet as a *confirm-before-commit* transition, not an
  undoable one. Part 5D inherits that classification and must not offer Undo for it.

## Logical column contract (decision 2)

- URL/query vocabulary gains one value: `stage=assessment`. Everything else stays a real stage.
- The server maps it to `('assessment_unscheduled','assessment_scheduled','assessment_completed')`.
  The mapping lives beside `BOARD_STAGES` in `src/lib/pipeline/stages.ts` so browser and server share it.
- Cursors already carry their sort (`src/lib/server/pipeline/board.ts:40-72`). They gain the column they
  were cut from, and a cursor whose column does not match the request is refused with the existing
  `Start this column again.` validation error — the same guard that already catches a mismatched sort.
- When the detailed toggle is on, the board asks for the three real stages exactly as it does today. The
  logical column is a presentation affordance, never a second stored truth.

## Query plan and indexes (decision 8) — settled

Every other board index is `(organization_id, stage, <sort>, id)`, so a three-stage predicate cannot read one
ordered range from any of them. The fix was to make the assessment stage set the index *predicate* instead of
the leading key. Measured, applied, and re-verified after the API change; the full measurement narrative and
the numbers live in the migration's own comment
(`20260902091400_pipeline_unified_board_and_presentation_setting.sql`, section 1) — not repeated here.

One correction worth keeping: a sort node does **not** break keyset correctness. The sort key ends in `id`,
so the order stays deterministic and the cursor still selects the right rows. It was only ever a performance
problem. An earlier draft of this packet said otherwise.

The three non-default sorts keep their sort node deliberately, on the judgment already recorded for
`opportunities_board_owner_idx`: more indexes on a table every Request writes to must be earned, and the
default sort is what every board load uses. **Revisit trigger:** a real organization whose assessment group
passes a few thousand open cards, or any report of a slow board under a non-default sort.

## Grouped read model (decision 3)

`pipeline_board_page` gains the assessment appointment for grouped rows. The joined `assessments` row is
already reachable — `private.opportunity_apply_stage` reads `assessment.starts_at` and
`assessment.completed_at` from the same relationship
(`20260820002553_quotes_request_conversion.sql:52-63`). The card payload gains one nullable field for the
scheduled instant, formatted with the organization's timezone the way every other board date already is.

Ordering is one keyset across all three states — never three lists stitched together — so a page boundary
cannot duplicate or skip a card that sits between two sub-states.

## Settings (decisions 6 and 7)

- Column on `organization_settings`, defaulting to the collapsed five-column view.
- New `public.save_pipeline_presentation(...)` following `save_organization_branding`
  (`20260824090000_contractor_settings_reconciliation.sql:506-574`) exactly: permission check, `for update`
  read, `expected_revision` mismatch returns `status: 'stale'` with editor name and time, update bumps the
  revision and stamps editor/time, changed value writes an `organization_settings_audit` row.
- New route under `src/routes/api/settings/`, mirroring `settings/branding/+server.ts`: permission gate,
  rate limit, JSON guard, Zod parse, `isStale`/`staleSettingsResponse`.
- New `Settings → Pipeline` page and a destination card on the Settings home, matching the existing
  `SettingsDestinationCard` grid. Explicit Save, no auto-save. Toast on save, per the standing rule.
- **Read path:** the preference is added to the `/api/pipeline/summary` payload, which the board already
  holds at `staleTime: 30_000` and which `invalidatePipeline` already reaches. Saving invalidates the
  Pipeline family, so the saving session updates immediately and any other open board picks it up on its
  normal refresh. The Settings page reads through its own settings query for the form's revision.

## Checklist

1. ~~Migration~~ **DONE 2026-08-24.** See "Migration layer: what shipped" below.
2. ~~`performance-review`~~ **DONE 2026-08-24, pass.**
3. ~~API~~ **DONE 2026-08-24.** See "API layer: what shipped" below.
4. ~~`performance-review`~~ **DONE 2026-08-24, pass with one deferral.**
5. UI, split into two sessions (Jafar, 2026-08-24):
   - ~~Slice A~~ **DONE 2026-08-24.** One horizontal board with two group headers and the pre-Draft
     boundary; grouped Assessment column with per-card state badge and appointment; per-card Draft drop
     eligibility; conversion confirmation. See "UI layer, Slice A: what shipped" below.
   - ~~Slice B~~ **DONE 2026-08-24, unverified in the browser.** Brief sub-state next action; Settings →
     Pipeline page. See "UI layer, Slice B: what shipped" below.
6. ~~`performance-review` + `svelte` for every `.svelte` file; `design` throughout.~~ **DONE 2026-08-24.**
   `svelte` autofixer clean on every changed file, `npm run check` 0 errors, Prettier clean.
   `performance-review`: ✅ Pass — no new routes or queries (reuses the already-reviewed `/move` and
   `/api/settings/pipeline` routes), no new `staleTime`/invalidation hazards, no new lists or bundle weight.
7. ~~Browser verification with Jafar~~ **DONE 2026-08-24.** Jafar verified both slices live and confirmed
   all acceptance checks pass. 5C-iii is closed.

## UI layer, Slice A: what shipped (2026-08-24)

- One horizontal board, single scroll: two `SectionBlock` groups (Requests, Quotes) side by side in
  `pipeline/+page.svelte`, fixed 280px columns (240px below 640px), the two groups' own borders read as the
  boundary before Draft. Column set per group comes from `REQUEST_COLUMNS_COLLAPSED` /
  `REQUEST_COLUMNS_DETAILED` / `QUOTE_COLUMNS` (new in `stages.ts`), switched by
  `summaryQuery.data.detailed_assessment_stages`.
- Grouped Assessment column: `OpportunityCard` gets `showStageBadge` — a small `Badge` (Unscheduled
  =warning, Scheduled=informative, Completed=success) plus the appointment time from `card.assessment` via
  the new `appointment()` formatter in `money.ts`, shown only when the column is the collapsed group.
- Per-card Draft eligibility needed no new logic — `draggingFromStage` already carries the real per-card
  sub-stage, so `allowedDragTargets` already discriminates `assessment_scheduled` (not convertible) from
  the other two. `dropRefused` in `PipelineColumn.svelte` was rewritten around `stagesInColumn` so it
  recognises "started in this column" for both a real column and the collapsed group uniformly.
- New `AssessmentEntryChoiceDialog.svelte`: only fires when a New request is dropped on the *collapsed*
  group (`stage === ASSESSMENT_GROUP`, `fromStage === 'new_request'`) — Schedule hands off to the existing
  `ScheduleAssessmentDialog` (aimed at `assessment_scheduled` via new `pendingCardTarget` state, since
  `stage` is the logical key there, not the real target); Add without scheduling commits
  `assessment_unscheduled` directly. Dragging *within* the collapsed group (e.g. unscheduled → completed)
  is deliberately a no-op — decision 4 routes that through the Brief, not a drop.
- New `ConvertToQuoteDialog.svelte`: fires on `DRAG_ACTIONS_NEEDING_CONFIRMATION` (`quote_convert`), names
  the client and request, generates a fresh `idempotencyKey` on confirm. `performMove` now surfaces
  `result.quote` and names the quote number in the success toast.
- Pinned horizontal scrollbar (Jafar's call, 2026-08-24, after seeing the board): `.pipeline__board`'s own
  scrollbar sits at the bottom of a box that grows with card count, so it could end up requiring a full
  page-scroll to reach. A second strip, `position: fixed` off the same `--shell-content-left/right/edge`
  vars `StickyActionBar` uses, mirrors the board's scroll position and stays pinned near the bottom of the
  viewport. Only shown when the board actually overflows (`ResizeObserver` + `MutationObserver` on
  `boardViewport`, since content-only overflow doesn't fire `ResizeObserver` by itself). Vertical scrolling
  is unchanged — the page still scrolls normally; only the x-axis scrollbar is pinned.
- Equal group height (Jafar's call, 2026-08-24): Requests and Quotes are separate flex items in
  `.pipeline__board`, so each sized to its own tallest column and could end on different lines.
  `.pipeline__board` is now `align-items: stretch`, and `.pipeline__columns` is `flex: 1 1 auto` so the
  shorter group's columns extend their drop zones to fill the equalized height rather than leaving blank
  space under a short row.

Tests: 168/168 pipeline tests pass, `npm run check` 0 errors, Prettier clean.

## UI layer, Slice B: what shipped (2026-08-24)

- New `OpportunityNextActionSection.svelte`, mounted first inside the Brief's `{#key opportunity.id}` block
  (`OpportunityBriefDrawer.svelte`), before Opportunity details. Renders only when `canEdit` and the card's
  stage is one of the three assessment sub-states: unscheduled → "Schedule assessment" (opens
  `ScheduleAssessmentDialog`, aimed at `assessment_scheduled`); scheduled → "Mark assessment complete"
  (direct `dragOpportunity` write, no dialog — the transition table already puts `assessment_complete`
  outside both `DRAG_ACTIONS_NEEDING_INPUT` and `_CONFIRMATION`, matching the board's own drop behavior for
  it); completed → "Create quote" (opens `ConvertToQuoteDialog`, the same dialog and copy the board's own
  Draft drop uses). All three write through `dragOpportunity` via a local `performMove` that mirrors
  `PipelineColumn`'s own one: loading/success/error toast, `invalidatePipeline`, and the quote-number toast
  wording on conversion. A successful conversion calls a new `onConverted` prop, wired to the drawer's
  existing `onClose` — the Brief closes itself, the same way a Lost card's open Brief is closed today.
- `Settings → Pipeline`: new `src/routes/(app)/settings/pipeline/+page.svelte`, built on `RecordFormLayout`
  exactly like `branding/+page.svelte` (query → local `$state` hydrated once via `untrack` → dirty check →
  explicit Save/Cancel → conflict banner naming the other editor). One `Toggle` inside a `SectionBlock`
  (`form`, `level={3}`) for `detailed_assessment_stages`. Save invalidates both `settingsPipelineKey` and
  the whole `['pipeline']` family (`invalidatePipeline`), per decision 7 — no new refresh path invented.
  `fetchSettingsPipeline`/`savePipelineSettings`/`settingsPipelineKey` added to `src/lib/settings/api.ts`,
  mirroring `fetchSettingsBusiness`/`saveBranding`. A destination card ("Pipeline", `layout-kanban` icon)
  added to the Settings home's existing "Business" `SectionBlock`, after Business hours.
- `npx vitest run` (project-wide): 130/133 files pass, 1056/1064 tests pass — the remaining 8 are the
  pre-existing, already-tracked failures in `eight-vitest-failures-in-the-quotes-and-team-specs.md`, none
  touched by this change. `npm run check`: 1 pre-existing, unrelated error in an untracked `communications`
  campaign file (`finalize_communication_email_domain_removal` not yet in generated types) — not from this
  session's changes, not fixed here.

## Migration layer: what shipped (2026-08-24, closed)

`supabase/migrations/20260902091400_pipeline_unified_board_and_presentation_setting.sql` and
`20260902091500` (the editor FK index), both applied to the linked project.

- `opportunities_board_assessment_group_idx` — the partial group index. Measured evidence in the table
  above and repeated in the migration's own comment.
- `organization_settings`: `pipeline_detailed_assessment_stages` (default false), `pipeline_revision`,
  `pipeline_updated_by` (→ `auth.users`, matching the other three sections), `pipeline_updated_at`, plus
  column grants and `organization_settings_pipeline_editor_idx`.
- `organization_settings_audit`'s `section` check widened to admit `'pipeline'`. **This was a blocker
  found only by inspecting the constraint** — the save function's audit insert would have failed at
  runtime without it.
- `save_pipeline_presentation(uuid, integer, boolean)` — copies `save_organization_branding` exactly.
- `pipeline_board_page` — gains the `assessment` logical column and returns `assessment_starts_at` /
  `assessment_ends_at`. The `assessments` join is safe against fan-out: `assessments.request_id` is UNIQUE.
- `src/lib/database.types.ts` regenerated. **Note:** the committed file was badly stale against the live
  schema, so this diff is larger than this part's own changes. It also *fixed* the four Team/Profile
  `npm run check` errors that the 5C-ii packet recorded as unrelated pre-existing failures — they were
  caused by the stale types, and `npm run check` is now **0 errors across 2411 files**.

Tests: `supabase/tests/database/pipeline_unified_board_and_presentation_setting.sql`, **28/28 passing**
against the linked project. The load-bearing ones page the grouped column two cards at a time through an
interleaved nine-card fixture and assert the walk matches the unpaged order card for card, plus a guard
assertion proving the walk actually crosses sub-state boundaries so the suite cannot pass vacuously.

Two fixture corrections found while running: the member role vocabulary is
`owner/admin/office/sales/field/finance` (no `worker`), and a `WITH ORDINALITY` alias must name all 30
returned columns — replaced with a plain `array_agg` over the function's own emitted order.

## API layer: what shipped (2026-08-24, closed)

**One migration was needed that this packet had not anticipated.** `private.pipeline_drag_transition_allowed`
is the authoritative drag gate and knew nothing about conversion, so the route could not have dispatched it
whatever it asked for. `supabase/migrations/20260902091500_pipeline_drag_converts_request_to_quote.sql` adds
exactly three pairs — `new_request`, `assessment_unscheduled`, `assessment_completed` → `quote_draft` —
applied and verified on the linked project. `assessment_scheduled → quote_draft` is refused, which is what
makes Draft a per-card target.

- `src/lib/pipeline/stages.ts` — `ASSESSMENT_GROUP`, `ASSESSMENT_GROUP_STAGES`, `BoardColumnKey`,
  `BOARD_COLUMN_KEYS`, `stagesInColumn`, `BOARD_COLUMN_LABELS`. The shared vocabulary both sides read.
- `src/lib/server/pipeline/board.ts` — `BoardCursor` gains `column`; the wire format is now
  `<column>:<sort>:<phase>:<value>|<id>`. A marker from before this change parses as garbage and is refused,
  which is correct: the board never carries a cursor across a control change.
- `src/routes/api/pipeline/opportunities/+server.ts` — accepts the column, refuses a cursor whose column or
  sort does not match **before the database is asked anything**, and returns `assessment: { starts_at,
  ends_at } | null` per card.
- `src/lib/server/pipeline/presentation.ts` + `/api/pipeline/summary` — the preference rides on the summary
  payload as `detailed_assessment_stages`, read **uncached** (see the deferral note below) and in parallel
  with the counts. The summary also now returns an `assessment` entry in `counts` and `value_totals`, added
  up server-side so the grouped heading cannot disagree with its three parts.
- `src/routes/api/settings/pipeline/+server.ts` — GET (form value + revision + last editor) and PATCH,
  mirroring `settings/branding` exactly. `pipelinePresentationSchema` in `settings.schema.ts`.
- `src/lib/pipeline/transitions.ts` — `quote_convert` action and `DRAG_ACTIONS_NEEDING_CONFIRMATION`.
  `allowedDragTargets` now answers the per-card Draft question the UI step needs.
- `src/routes/api/pipeline/opportunities/[id]/move/+server.ts` — conversion dispatch. `idempotency_key` is
  optional in the schema and required by the route for this one action.

**The request-hash risk resolved differently than the packet guessed.** The board does not derive a pricing
fingerprint at all — the server sends `board-drag:<opportunity id>`, because nobody was looking at pricing
when they dragged. Copying the Request page's `rev-N:lines-N` would be a claim about a screen that was never
open. It is stable across a retry of the same drag, which is all the hash is for.

Tests: 190 passing across the pipeline and board specs, including the grouped column's cursor round trip
across a sub-state boundary, three cursor-replay refusals (other column, other sort, pre-change format), and
conversion refused for a booked assessment, for a missing key, and reported as a conflict when the request
already has a quote. `npm run check` 0 errors across 2417 files. Prettier clean on every changed file.

**Measured 2026-08-24** on the linked project. The grouped read plans as
`Index Scan Backward using opportunities_board_assessment_group_idx`, Index Cond `organization_id` only —
the stage predicate is proven away and there is no Sort node, matching the migration's own measurement. The
`assessments` join resolves through `assessments_request_unique` (`Index Cond: request_id = o.request_id`,
proven with bitmap/seq scans disabled), one lookup per outer row against a page capped at 51. The preference
read is a primary-key lookup on `organization_settings` (2 buffers).

**Deferred from this review:** `Memory/deferred/board-presentation-and-formatting-are-read-behind-a-settings-permission.md`
— both the preference and the pre-existing formatting read sit behind `settings.business.view`, so a member
with that permission denied by override silently gets the default board. Needs a security-definer read gated
on `pipeline.view`; batched with a future migration rather than run alone.

## Acceptance checks

- Five columns by default, one horizontal scroll, both group totals correct, boundary visible before Draft.
- Toggle on → seven columns, every 5C-ii drag behavior unchanged. Toggle off → five, no truth rewritten.
- Grouped Assessment column: correct merged count and total, correct state badge per card, appointment shown
  for scheduled cards, keyset paging correct across sub-state boundaries with no duplicate or skipped card.
- A cursor from another column or another sort is refused, not silently paged.
- New requests → Assessment opens the two-choice dialog; Schedule primary, Add without scheduling secondary;
  card stays in New requests until the chosen action succeeds; cancel changes nothing.
- New requests → Draft and Assessment completed → Draft convert after confirmation; the Request card stays
  until the Quote exists, then the Quote card appears in Draft. A scheduled-assessment card cannot target
  Draft at all. Cancel or failure changes nothing.
- Brief shows exactly one correct next action per sub-state.
- Settings: owner/admin only, explicit Save, stale-revision conflict reports the other editor, audit row
  written, toast shown, board reflects the change without a manual reload.
- `EXPLAIN` evidence recorded for the grouped read. Prettier clean; changed-file `npm run check` clean.

## Source pointers

- `docs/sales-pipeline-behavior-contract.md` — "First-release board" (the five-column default and toggle),
  "Movement and automation" (confirmation vs. Undo).
- `parts/05b-drag-and-move-api.md` — the approved transition table this part extends with conversion.
- `parts/05c-ii-drag-gesture.md` — the server-confirmed drop pattern and the `div[role="button"]` card.
- `supabase/migrations/20260820002553_quotes_request_conversion.sql` — `convert_request_to_quote`.
- `supabase/migrations/20260824090000_contractor_settings_reconciliation.sql:506` — the Settings write pattern.
- `supabase/migrations/20260819002041_pipeline_board_page_sort_and_filters.sql:40` — existing board indexes.

## Non-discoverable risks

- Every board index is stage-prefixed; a grouped read without its own partial index silently gains a sort
  node and breaks keyset correctness rather than failing loudly.
- `convert_request_to_quote` needs an idempotency key **and** a request hash. The Request page derives the
  hash from cached pricing (`requests/[id]/+page.svelte:237`); the board has no pricing cache, so the drag
  path must derive its own stable fingerprint rather than copying that line.
- The `unscheduled` status is convertible but `scheduled` is not, so column-level drop rules are wrong here.
- `dropRefused` is currently per column. Making it per card must not weaken the existing refusal guard.

## Non-goals

Custom stages. Part 5D's Undo. Mobile. Any change to stored stage truth, history, or reporting.
