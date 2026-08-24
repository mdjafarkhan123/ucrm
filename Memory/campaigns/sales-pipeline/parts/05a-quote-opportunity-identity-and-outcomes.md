# Part 5A: Quote-backed Opportunity identity and automatic outcomes

## Scope

Database only. Gives a Quote its own Opportunity, exactly parallel to how a Request already gets one, and
wires the automatic outcomes the approved contracts already commit to. No API routes, no UI. 5B (drag/API)
and 5C (board UI) build on this and are separate sessions.

## Approved behavior this packet implements

- `docs/sales-pipeline-behavior-contract.md`: "Every Quote will automatically have exactly one Opportunity,
  created with the Quote" (line 22); "One Opportunity does not continue from Request to Quote" (line 23);
  "Won is automatic when a Quote is approved" (line 73); Lost stays deliberate and reopen requires a short
  explanation (lines 75-81).
- `docs/quote-behavior-contract.md` lifecycle table (lines 102-116): Approve → Pipeline marks only this
  Quote Opportunity Won. Decline → Pipeline atomically marks only this Quote Opportunity Lost, no separate
  Pipeline reason. Declined → Revise/reopen → Pipeline records Reopened, returns to the Quote Draft
  projection. Approved → Begin material revision → Pipeline Won reopens only if no Job exists (always true
  pre-Jobs). Line 403-404: "Approval and decline must update the backing Quote Opportunity atomically."
- Confirmed with Jafar 2026-08-23: no extra manual confirm step before Lost — the contract's atomic design
  already covers the "recoverable deal" concern via one-click Revise/Reopen back to Draft.

## Correction after reading the actual schema (important — read this before the checklist)

The Quotes campaign already built the identity foundation as forward-looking groundwork while Part 5 was
blocked. **Do not re-add or touch these — they already exist:**

- `opportunities.quote_id`, its `opportunities_quote_organization_fk`, `opportunities_single_source` check
  (`request_id is null or quote_id is null`), and the partial unique index `opportunities_quote_unique` —
  all added in `supabase/migrations/20260820002553_quotes_request_conversion.sql`.
- Both `public.create_quote` (`20260820160000_quote_workspace_commands.sql`) and
  `public.convert_request_to_quote` (same file as above) already insert the matching `opportunities` row
  inline, with the comment "the stage trigger parks it off the board until the Quote columns exist." 5A
  must not touch either function.
- `private.opportunity_apply_stage()` already has a branch: `if new.quote_id is not null then
  resolved_stage := 'request_closed'`. 5A replaces only this one branch with real derivation from
  `quotes.status` — everything else in that function is untouched.

So 5A is real-stage-derivation-plus-outcome-automation only, not identity plumbing.

## Design decisions (this session)

1. **Automatic Won/Lost/Reopen for Quotes is trigger-based**, mirroring how Request-side stage derivation
   already works — not a new client-facing RPC. One `AFTER UPDATE OF status ON quotes` trigger, guarded by
   the opportunity's *current* `outcome` (not by inspecting `old.status`), so every path is naturally
   idempotent:
   - `new.status = 'approved'` and `outcome = 'open'` → Won.
   - `new.status in ('declined', 'archived')` and `outcome = 'open'` → Lost. This covers Decline *and* a
     staff member archiving a still-open (draft/awaiting/changes-requested) Quote from its own page — no
     separate Pipeline RPC needed for that case.
   - `new.status in ('draft', 'awaiting_response', 'changes_requested')` and `outcome <> 'open'` → Reopen.
     Covers Revise/reopen-from-Declined, Begin-material-revision-from-Approved, and restoring an archived,
     still-undecided Quote back into active work.
   - Anything else (e.g. archiving an already-Approved/Won quote, restoring straight back to
     approved/declined) touches no outcome field — verified case by case in the design notes below.
   Confirmed with Jafar 2026-08-23: no extra manual confirm step before Lost, and no required-explanation
   param added to `revise_quote` — the existing "Started a new draft from the sent version" activity entry
   is the record.
2. **`pipeline_mark_opportunity_lost` / `pipeline_reopen_opportunity` are untouched.** Their existing
   refusal of quote-backed opportunities stays correct and stays in place — quote-backed Lost/Reopen now
   flows entirely through the `quotes.status` trigger above, never through these RPCs.
3. `opportunity_outcome_events` gains `prior_quote_status` alongside the existing `prior_request_status`,
   and a `'won'` event type (today only `'lost'`/`'reopened'` exist — Won was deliberately left unbuilt
   pending a real caller; see that migration's own comment). A `'won'` row carries no reason/note/prior-
   status/explanation, matching how `'reopened'` rows already carry none of the `'lost'` fields.

## Checklist

- [ ] Extend the `opportunities.stage` check constraint with `quote_draft`, `quote_awaiting_response`,
      `quote_changes_requested`. `request_closed` keeps its existing meaning and stays the off-board
      parking value for a decided/closed Quote too (approved/declined/archived/converted) — no new
      `quote_closed` value; it's not a board column, so nothing needs to distinguish it further.
- [ ] Rewrite only the `new.quote_id is not null` branch of `private.opportunity_apply_stage()` to derive
      the real stage from `quotes.status` (draft/awaiting_response/changes_requested → the three `quote_*`
      stages; approved/declined/archived/converted → `request_closed`). Everything else in the function,
      and every other file that already writes to `opportunities`, is untouched.
- [ ] New `AFTER UPDATE OF status ON quotes` trigger, mirroring `opportunity_resync_from_request`'s
      touch-to-resync pattern: always touches the matching `opportunities` row so the stage recomputes;
      additionally performs the guarded Won/Lost/Reopen outcome write described in "Design decisions"
      above, in the same `UPDATE ... opportunities` statement (one write, not two).
- [ ] `opportunity_outcome_events`: add `prior_quote_status text` (mirrors `prior_request_status`'s shape,
      but no fixed vocabulary check — Quote status values, not Request ones), add `'won'` to the
      `event_type` check, extend `opportunity_outcome_events_type_fields_consistent` so a `'won'` row
      requires no reason/note/prior-status/explanation (same shape as today's implicit rule for those
      fields), and widen the `restores_event_id` FK's implied use so a `'reopened'` row may restore either
      a `'lost'` or a `'won'` event.
- [ ] Backfill: for every existing quote-backed `opportunities` row, resync its stage now that real
      derivation exists (they're currently parked at `request_closed` from the pre-5A branch), and backfill
      `outcome`/`outcome_at` directly (no synthetic event row — there was no Pipeline to log one against at
      decision time) for quotes already `approved` (→ `won`), `declined` (→ `lost`), `converted` (→ `won`,
      permanent), or `archived` (→ `won`/`lost` by reading the quote's own `previous_status`, mirroring the
      Won/Lost/open rules above; an archived quote whose `previous_status` was still open-ended
      draft/awaiting/changes counts as `lost`).
- [ ] Tenant isolation, RLS, and grants match the existing Request-side pattern exactly — members read,
      nothing writes outcome/stage except the definer functions and triggers. `pipeline_mark_opportunity_lost`
      / `pipeline_reopen_opportunity` are not modified.
- [ ] pgTAP: direct-creation Quote's existing Opportunity lands in `quote_draft` once the trigger recomputes
      it; Request-converted Quote's Opportunity does too, while the Request's own card is at
      `request_closed`; Approve → Won; Decline → Lost; archiving a still-open Quote → Lost via the same
      path (no separate RPC); archiving an already-Approved Quote → no duplicate/incorrect outcome write;
      Revise/reopen from Declined → back to `quote_draft`, `outcome` back to `open`; Begin-material-revision
      from Approved → Won reopens the same way; restoring an archived-but-still-open Quote → reopens;
      restoring straight back to approved/declined → no-op on outcome; backfill produces correct
      outcome/stage for pre-existing decided quotes.

## Closed 2026-08-23

Migration `supabase/migrations/20260902090700_pipeline_quote_stage_and_outcome_automation.sql` applied to
the linked remote project. All checklist items shipped as designed, with two corrections found during
verification:

- The `opportunity_outcome_events_type_fields_consistent` constraint's `'won'` branch originally forbade
  `prior_quote_status`, but the trigger writes it for audit parity with `'lost'`. Fixed to allow it.
- `private.opportunity_resync_from_quote()`'s opportunity lookup filtered on `quote_id` alone, which cannot
  use the composite `opportunities_quote_unique (organization_id, quote_id)` index as an equality condition
  — confirmed by `EXPLAIN` showing a `Seq Scan`. Fixed by adding `organization_id` to the lookup and to all
  four backfill joins; re-verified with `EXPLAIN` showing `Index Scan using opportunities_quote_unique`.
  Caught by the required `performance-review` gate — see that skill's report for this session.

pgTAP: `supabase/tests/database/pipeline_quote_stage_and_outcome_automation.sql`, 28 assertions, all passing
against the linked remote project (transaction rolled back). Covers stage derivation on insert, ordinary
stage moves touching no outcome, Approve→Won, Begin-material-revision→Won-reopen, Decline→Lost,
Revise/reopen→Lost-reopen, abandoning a stale Draft via the Quote's own `archive_quote` (no separate
Pipeline RPC), archiving/restoring an already-Won quote leaving outcome untouched, tenant isolation, and a
CHECK-constraint sanity check. Live data verified post-migration: pre-existing quotes correctly resynced
(3 `awaiting_response` → `quote_awaiting_response`/open, 2 `approved` → won, ~28 `archived` → lost, all with
backfilled `outcome_at`).

`pipeline_mark_opportunity_lost` / `pipeline_reopen_opportunity` were not touched, per the design decision.

## Non-goals (later subparts)

- No drag/API endpoint (5B). No board UI, no Quotes column group, no card rendering (5C).
- No money/column totals for the Quotes group — that is 5C, reusing Part 2's existing money primitives.

## Source pointers

- `supabase/migrations/20260818133431_sales_pipeline_opportunity_foundation.sql` — Request-side pattern to
  mirror (`private.request_pipeline_stage`, `opportunity_apply_stage` trigger, unique constraints).
- `supabase/migrations/20260819080000_pipeline_outcome_engine.sql` — the Lost/Reopen engine being extended;
  note line ~271: `pipeline_mark_opportunity_lost` currently refuses quote-backed opportunities outright.
- `supabase/migrations/20260821160000_quote_publication_and_decisions.sql`,
  `20260822090000_quote_customer_views_and_decisions.sql` — where `quotes.status` transitions to
  `approved`/`declined` and `record_quote_decision` already lives.
- `src/lib/pipeline/stages.ts` — board stage vocabulary the browser and server both read.
