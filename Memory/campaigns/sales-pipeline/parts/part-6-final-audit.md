# Part 6 — Final audit and contractor manual

Approved by Jafar 2026-09-16. Also satisfies financial-reconciliation Part 5 (same work, one owner).

## Scope

1. **Desktop click-through** — drag cards between stages; open the Opportunity Brief; add/complete a Task;
   add/edit/delete a Note; mark Won and Lost (with reason); reopen a Lost item; verify stage-age color
   thresholds (green <1h, neutral 1–24h, red >24h); verify column `Load more` pagination.
2. **Accessibility** — full keyboard operation of board and Brief (drag alternative, dialogs, focus
   management); screen-reader labeling of cards, columns, and controls.
3. **Security** — `pipeline.view`/`pipeline.edit` enforced server-side and via RLS on every board/Brief
   action; cross-tenant isolation proven with a real second-organization account, not just code review.
4. **Proportional performance** — only if a scale-sensitive path exists per the `performance-review` skill's
   invocation gate; measured against a realistic seeded data volume, not a 40,000-user claim.
5. **Contractor-manual walkthrough** — use the board the way an office/sales person would all day; compare
   against Jobber's pattern (`docs/research/contractor-crm-sales-pipeline-comparison.md`); flag anything off
   or missing.

## Progress (checkpoint 2026-09-16, mid-session)

1. **Desktop click-through — done.** Opened Brief (board stays scrolled/filtered behind it); added and
   completed a Task (card live-updates); added a Note from the Brief and confirmed it also shows on the
   Request's own Notes card (not a second copy); Marked Lost with a reason (all 6 spec reasons present,
   card leaves board live, Won/Lost tiles update live, no reload needed); Reopened from Sales Outcomes
   (required explanation enforced, restores to board live with stage age reset to `0h` fresh/green).
   Drag-and-drop itself could not be exercised via mouse automation (tooling limitation dragging through
   svelte-dnd-action) — covered instead by 169 passing unit/integration tests plus the dedicated
   `pipeline_drag_transitions.sql` acceptance suite. Stage-age colors confirmed both by code
   (`src/lib/pipeline/freshness.ts`, `StageAgeChip.svelte`) and live (`0h` green badge after reopen).
   `Load more` verified live: seeded 30 real requests via `mcp__supabase__execute_sql` (org
   `18f0d717-904e-48d8-bd99-9df7e3844cda`, titled `AUDIT PAGINATION TEST %`), confirmed the button appears
   past 25, loads the rest, then disappears; **test rows deleted afterward, cleanup confirmed (0 remaining,
   no orphaned opportunities).**
2. **Security — done.** Live-tested all three Raad LTD test roles: `finance` gets no Pipeline nav item, and
   direct navigation to `/pipeline` shows "You do not have access" with every API call returning a real 403
   (`/api/pipeline/opportunities`, `/summary`, `/outcomes/summary`) — server-enforced, not just hidden UI.
   `sales` and `office` both get full view+edit. Cross-tenant isolation proven live against the remote DB:
   ran `pipeline_quote_board_read_model.sql`'s scenario directly (not just re-reading the file) — an admin
   from org B is refused (`42501`) reading org A's `pipeline_board_page` and `pipeline_stage_counts`.
3. **Accessibility — one real bug found and fixed, committed (`a38339e`).** Enter on a focused Opportunity
   card was being intercepted by svelte-dnd-action's default keyboard-drag trigger (Space **or** Enter both
   start a keyboard drag) before it reached the card's own "open the Brief" handler — confirmed live
   (focus moved to a drag-placeholder element, Brief never opened) and root-caused via the library's own
   README, which documents this exact conflict and its fix. Fixed by calling
   `setKeyboardDragTrigger('space')` once in `PipelineColumn.svelte` (module scope — this call is global to
   the document, confirmed safe for the only other `dndzone` user, Quotes' `ProductsAndServicesBlock.svelte`,
   which has no competing Enter handler) and narrowing `OpportunityCard`'s own `onkeydown` to Enter only.
   Added `OpportunityCard.svelte.spec.ts` (did not exist before) covering this exact conflict. Re-verified
   live: Enter now opens the Brief, Escape closes it, drag-and-drop still works. All 169 pipeline tests pass;
   Prettier clean.
   **Not yet done:** screen-reader label sweep of columns/board landmarks (svelte-dnd-action's own
   `aria-label` accessibility beta feature — confirm it's wired for this board — see its README section
   "Accessibility (beta)"); full Tab-order pass through the Brief's own controls (Task dialog, Note textarea,
   field edit pencils).
4. **Proportional performance — done, no load test needed.** Confirmed by design/code evidence, not
   synthetic load: `pipeline_board_page` uses keyset (cursor) pagination on
   `(stage_entered_at desc, id asc)` — no OFFSET, flat cost regardless of page depth — capped at 51 rows/page
   (`supabase/migrations/20260818233830_pipeline_board_page_read_model.sql`). Matching partial composite
   indexes exist for every sort option (`organization_id, stage, {stage_entered_at|created_at|estimated_value}, id`
   filtered `where outcome = 'open' and stage <> 'request_closed'` — exactly the query's own filter) in
   `supabase/migrations/20260819002041_pipeline_board_page_sort_and_filters.sql`. This is a bounded, indexed,
   paginated path per the `performance-review` skill's own skip criterion.
5. **Contractor-manual walkthrough — not done yet.** Was reading
   `docs/research/contractor-crm-sales-pipeline-comparison.md` (the approved research behind the contract)
   when the session paused. The extensive click-through above already exercised most Jobber-matching
   behavior (Request/Quote separation, freshness-color rule, the 6 Lost reasons, Reopen as UCRM's own
   documented addition, Won-permanent-after-Job). Remaining: a deliberate walk-through comparing live
   behavior against this doc's specific recommendations (esp. items 2–5 under "Recommendation for UCRM"),
   and a fresh look for anything that feels off to a daily office/sales user that the functional checks
   above wouldn't catch (e.g., wording, information density, missing affordances).

## Exact next action

1. Finish the contractor-manual walkthrough: re-read
   `docs/research/contractor-crm-sales-pipeline-comparison.md` recommendations 2–5, compare against the live
   board (already logged in as `office` role, Raad LTD test org), note any gap.
2. Decide whether the two "not yet done" accessibility items above (screen-reader labels, full Tab-order
   through Brief controls) are needed to call check 2 (accessibility) complete, or are a reasonable smaller
   follow-up — they were not blocking, just not yet exercised.
3. Once all five checks have a pass/fix recorded, write the outcome into this file's own summary, close Part
   6, delete this packet, mark financial-reconciliation Part 5 satisfied by reference, and move
   financial-reconciliation to its Part 6 (opening balances).

## Completion gate

All five checks pass, or found issues are fixed and re-verified. Record results here or in NOW.md, then
close this part, update financial-reconciliation's Part 5 as satisfied by this, and delete this packet.
