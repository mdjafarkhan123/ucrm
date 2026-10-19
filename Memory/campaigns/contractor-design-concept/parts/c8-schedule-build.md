# Schedule build — branch handover

**Stage:** Built and branch-verified, waiting for Claude's review/merge. No merge to main by Codex.
**Branch:** `codex/approved-shared-schedule-build`; worktree `/home/jafar/.codex/worktrees/approved-shared-build/Ucrm`;
claim `fff612924b43` retained until integration. Pencil and design skills stayed read-only.
**Agreement:** `c8-schedule.md`: four screens, Schedule pop-ups and three Jobs dialogs approved.

## Delivered

- Calendar toolbar, Week/Day/Month grids, kind-coloured cards, silver completed states, colour key,
  record/fact tiles, preview headers/status/people/timer panel, Unscheduled age pills and Map stop styling.
- Event completion: server-owned nullable timestamp; tenant-filtered, Zod-validated, permission-checked POST.
  Conditional update preserves the first completion under retries; completion refreshes the Schedule query.
- Final visit, Create visits and Apply to later visits match their approved frames. Create waits for parent
  writes on both Schedule and Job details, blocks repeat clicks and keeps dates after failure.
- Book work reuses PickedClient; Change property is a small secondary map-pin button there and in New job.
- Jafar clarified 2026-10-19: the app fills its available width; 1440 is only the Pencil comparison width.
  Removed PageContainer's 1280 cap; deliberately narrow forms retain 640.

## Evidence and outside state

`docs/evidence/2026-10-19-schedule/README.md` records commands, screenshots, sample-vs-live proof and limits.
Week/Day/Month/Map and the three Jobs dialogs checked light/dark; wider-window and 390 overflow checks,
keyboard move/cancel and preview dismissal checked. Event completion's full journey proven in the live branch.

- 18 focused tests pass; the two affected browser files reran after refinements: 11 pass. Edited Svelte
  components compile with zero warnings/errors. Existing autofixer navigation/reset/imperative-map advisories
  retained. Full-project checks deferred per Jafar.
- Migration `20261019080728_schedule_event_completion.sql` **already applied remotely**, transactionally with
  its ledger insert. MCP confirmed the column and version. Do not reapply; no RLS/permission changes.
- Completed proof event `42ff0305-725e-4cd3-b174-2c6cffbcdbce` remains. No hard-delete. Customer jobs were not
  changed. Rare-dialog and waiting-age proof used temporary in-memory harnesses, removed before commit.
- Two real Map stops shared a stored location, so the route capture has overlapping pins. Live Sunday
  week-start retained; no new setting added. Phone layouts remain outside this desktop campaign.

## Next

Claude reviews the branch, including the full-width clarification, and merges approved work. After safe
integration release the claim and archive the temporary worktree. Check the newly approved shared-part queue
before starting another batch. Shared components were pushed at `44782c74`; main Schedule slice at `07353195`,
with final visual refinements saved in the following commit.
