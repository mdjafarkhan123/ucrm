# Part 5B: Forward-only drag with required action

## Scope

The drag endpoint only. No board UI, no drag gesture, no drop-target styling — that's 5C. This part answers
"is this move real, and if so what does it actually do" for a card dropped on a column, for both the
Request group (already on the board) and the Quotes group (added by 5A, not yet rendered).

## Approved transition table (confirmed with Jafar, 2026-08-23)

Toured `.claude/skills/jobber/jobber-02-requests-leads.md` §4.6.1's "Movement" paragraph first. Neither
group has a drag target for "closed" — converting/completing/archiving a card takes it off the board
entirely, same as it already does for Requests, so 5B only covers moves between columns that actually
exist on a board: 4 for Requests, 3 for Quotes.

| From | To | Allowed | Action |
| --- | --- | --- | --- |
| New requests | Assessment unscheduled | Yes | Turn on the assessment, no date |
| New requests | Assessment scheduled | Yes | Create + schedule in one save (needs a start/end time) |
| New requests | Assessment completed | **No** | Would need two commands (create, then complete) chained |
| Assessment unscheduled | Assessment scheduled | Yes | Schedule the existing assessment |
| Assessment unscheduled | Assessment completed | Yes | Complete it, no date needed |
| Assessment scheduled | Assessment completed | Yes | Complete it |
| Draft | Awaiting response | Yes | Send the quote (`publish_quote`) |
| Draft | Changes requested | No | Not a single real action |
| Awaiting response | Changes requested | **No** | Only the client's own decision does this; the card moves there by itself when they do |
| Changes requested | Draft (Revise) / Awaiting response (Republish) | **No, as a drag** | Both are real staff actions but backward on the board; they stay Quote-page actions. The card jumps back on its own once staff uses them — the same way un-completing an assessment already moves a card backward today |
| Any other backward move | No | — |

Jafar's exact confirmation: refuse Awaiting response → Changes requested and all backward dragging; keep
customer-requested changes automation-only; revise/republish/reopen/restore remain Quote-page actions;
describe Draft → Awaiting response as publishing/marking awaiting response, not guaranteeing delivery
(matches `docs/quote-behavior-contract.md` line 105: "failed transport does not undo publication").

Source-code correction found while implementing: `publish_quote` only accepts `status = 'draft'`
(`supabase/migrations/20260821160000_quote_publication_and_decisions.sql:129`). The contract's row 111
("Changes requested → Republish unchanged") is not actually callable yet — there is no single command from
`changes_requested` straight to `awaiting_response` today; only `revise_quote` (→ draft) exists. This
doesn't change the approved table (both exits were already refused as drags), just narrows what "stays a
Quote-page action" currently means in practice.

## Why a new migration, not pure API

`opportunities` grants `authenticated` no table-level select at all beyond two narrow column grants
(`outcome_at`/`current_outcome_event_id`, `quote_id` — see `20260818232309_pipeline_opportunity_ownership_value_dates.sql:222`
and later grants). The API route has no way to learn a card's current stage or which record backs it
without a new SECURITY DEFINER function. That function is read-only by design: it validates permission and
the transition, then hands back `{organization_id, request_id, quote_id, from_stage}`. It performs no
write — the assessment/quote command that follows still owns its own atomicity and its own guards, exactly
like `publish_quote` already does for the Quotes side.

## What shipped

- `supabase/migrations/20260902090800_pipeline_drag_transitions.sql`:
  - `private.pipeline_drag_transition_allowed(from_stage, to_stage)` — the one allow-list, immutable SQL,
    must stay in sync with `src/lib/pipeline/transitions.ts`'s copy (the TS copy is UI/error-message only;
    this function is the actual gate).
  - `private.pipeline_lock_opportunity_for_drag` — locks the opportunity row and checks `pipeline.edit`,
    deliberately a standalone copy of `private.pipeline_lock_opportunity_for_outcome` rather than a shared
    call, so Part 5A's closed outcome engine file stays untouched.
  - `public.pipeline_drag_opportunity(target_opportunity_id, to_stage)` — the read-only gate the route
    calls first.
- `src/routes/api/pipeline/opportunities/[id]/move/+server.ts` — `pipeline.edit`-gated. Calls the gate RPC,
  then dispatches: assessment upsert (+ guarded `requests.status` bump, run together via `Promise.all`),
  assessment completion, or a `quote_versions` lookup for the current draft's `revision` followed by
  `publish_quote`. Deliberately does **not** reuse the existing `PUT /api/requests/[id]/assessment` route's
  logic — that route also handles assignees, which the drag's minimal scheduling dialog does not collect;
  duplicating the ~10-line status side effect here was judged safer than refactoring a protected, untested
  file for this.
- `src/lib/pipeline/stages.ts` — added `QUOTE_BOARD_STAGES` and `isQuoteBoardStage`, additive only.
  `BOARD_STAGES` (what 5C's board actually renders) is untouched.
- `src/lib/pipeline/transitions.ts` — `dragActionFor`/`allowedDragTargets`, the shared (browser + route)
  transition table.
- `src/lib/server/validation/pipeline.schema.ts` — `dragOpportunitySchema`.
- `src/lib/pipeline/api.ts` — `dragOpportunity()` client wrapper, for 5C to call.
- Tests: `supabase/tests/database/pipeline_drag_transitions.sql` (pgTAP, 17 assertions, verified against
  the linked remote project), `src/routes/api/pipeline/opportunities/[id]/move/move.spec.ts` (vitest, 15
  cases). `performance-review` run on both layers — parallelized the one independent-writes branch with
  `Promise.all`; no index or query-shape problems found.

## Non-goals (5C)

No drag gesture, no drop zones, no dialog UI for the one action that needs input (scheduling), no Quotes
column group rendering. 5C wires all of that to `dragOpportunity()` and `allowedDragTargets()`.

## Source pointers

- `docs/sales-pipeline-behavior-contract.md` "Movement and automation" and `docs/quote-behavior-contract.md`
  lifecycle table (lines 102-116).
- `parts/05a-quote-opportunity-identity-and-outcomes.md` — what 5B's quote-side action reacts to
  (the `AFTER UPDATE OF status ON quotes` trigger recomputes stage automatically once `publish_quote` runs).
- `supabase/migrations/20260818133431_sales_pipeline_opportunity_foundation.sql` — `request_pipeline_stage`,
  the derivation this part's assessment writes feed.
- `supabase/migrations/20260819080000_pipeline_outcome_engine.sql` — the lock-and-authorize pattern this
  part's `pipeline_lock_opportunity_for_drag` mirrors.
