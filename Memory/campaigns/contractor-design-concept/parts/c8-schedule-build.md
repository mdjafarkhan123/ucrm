# Schedule build — branch handover

**Stage:** Merged 2026-10-19 at Jafar’s explicit request, superseding the earlier Claude-only merge boundary.
**Branch:** `codex/approved-shared-schedule-build`; worktree `/home/jafar/.codex/worktrees/approved-shared-build/Ucrm`;
claim `fff612924b43` releases after the successful integration push. Pencil and design skills stayed read-only.
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

Continue the remaining approved shared-parts queue. Integration preserved current main's batch 5/6 approvals
and design skills. The only conflict was the campaign checkpoint, resolved by retaining both newer design
approvals and completed build status. Application code matches the already verified build branch. Claude's
uncommitted `concept.pen` remains untouched in his main workspace. Main was published from a clean integration
worktree; the local design checkout can fast-forward when Claude finishes its active drawing work.
