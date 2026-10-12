# Part 7 Weekly approval — in progress

**Branch:** `codex/time-clock-part-7`, folder `/home/jafar/ucrm-time-clock-p7` (node_modules linked to main's).
**Claim:** `b6508444838c` (owner `claude-time-clock-p7`); keep it until merged.
**Plan:** `docs/time-clock-behavior-contract.md` § Weekly approval.

## Done (2026-10-12)

- Migration `20261210090000_weekly_approval` **applied to the remote database** and recorded. Entries carry
  `approved_at`/`approved_by`; `private.change_time_entry` and `private.remove_time_entry` refuse approved
  hours without `time.track_team` (P0410); moves keep approval; history gains `approved`. New
  `timesheet_approval` (preview) and `approve_time_entries`. Reads return `approved`, `unapproved_count`,
  `can_approve`. Types regenerated.
- Rolled-back proof passes: `docs/research/time-clock-weekly-approval-2026-10-12/database-proof.sql` and
  `-output.txt` (crew refused on approved hours on Timesheets and Job Labor; manager still edits; stays
  approved after a move; history added → approved → changed; second approve is 0; future day refused).
- Route `src/routes/api/time-clock/timesheets/approval/+server.ts` (GET preview, POST approve) with tests.
- Screens: `ApproveTimesheetsDialog.svelte` (day, people checklist, running-timer warning); Approve button on
  Timesheets (managers, preview prefetched on hover); "Approved" on entries, person rows, Job Labor; notice in
  the edit dialog for approved entries; history wording.
- `npx vitest run src/lib/time-clock src/routes/api/time-clock`: 116 passed.

## Next

1. `npm run check` — the last run died with a Node out-of-memory error, not a type error. Retry with
   `NODE_OPTIONS=--max-old-space-size=8192 npm run check`; fix any errors.
2. Run the Svelte MCP autofixer on `ApproveTimesheetsDialog.svelte`; `npm run lint` on changed files.
3. Live journey on the dev app (owner login, then Field member): approve last week, check the crew member's
   entry has no Edit/Delete and Job #20 Labor shows "Approved"; owner edits an approved entry.
4. Design screen check at 1440px and 390px: Approve dialog (loaded, nothing waiting, running warning),
   approved entries and badge, Labor line, edit notice. Save screenshots and `live-journey.md` in the
   research folder.
5. Merge into main per `docs/agent-concurrency.md`, mark Part 7 done in `ROADMAP.md`, release the claim.
