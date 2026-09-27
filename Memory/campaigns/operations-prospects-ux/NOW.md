# Operations and Prospects UX: Current Checkpoint

## Goal

Use the shared accessible dialog for compact Operations review and a dedicated route for the data-heavy Prospect experience.

## Current part

Part 3 Prospect detail, resumed 2026-09-27. A route `/jafar/prospects/[prospectId]` was built and
browser-verified this morning (single page, sectioned card layout matching Organizations' style, no tabs,
loading skeleton, not-found error state, four real stages, the correction/package/payment forms, the
not-proceeding confirm dialog, mobile width) by a session whose transcript is no longer reachable. It was never
committed, and a second, unrelated session (data-cache-architecture) deleted the untracked file believing it
was a stale unrequested file from an earlier runaway agent. **The file is confirmed permanently lost — no git
history, no trash, no local-history copy, no reachable transcript.** This is a real data-loss incident, not a
resumable checkpoint; the work described above must be rebuilt from scratch against the approved spec.

## Exact next action

Tell Jafar the route was lost and ask whether to rebuild it now from
`Memory/campaigns/operations-prospects-ux/parts/03-prospect-detail-page.md` before touching the old list page's
inline panel. Do not assume the rebuild plan is identical to what was lost — re-present the movement plan per
the part packet's own "Work" steps and get approval before building, same as any fresh start on this part. The
old inline detail panel in `src/routes/jafar/(protected)/prospects/+page.svelte` has not been touched and still
works; nothing there was lost.

## Essential pointers

- `Memory/campaigns/operations-prospects-ux/parts/03-prospect-detail-page.md`
- New page: `src/routes/jafar/(protected)/prospects/[prospectId]/+page.svelte`

## Completion gate

The detail route preserves every existing Prospect field, action, permission, and cache update without backend
changes.
