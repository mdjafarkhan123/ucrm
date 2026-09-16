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

## Completion gate

All five checks pass, or found issues are fixed and re-verified. Record results here or in NOW.md, then
close this part, update financial-reconciliation's Part 5 as satisfied by this, and delete this packet.
