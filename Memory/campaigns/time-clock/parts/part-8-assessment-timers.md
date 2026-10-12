# Part 8 — Assessment timers

**Campaign:** time-clock · **Plan:** `docs/time-clock-behavior-contract.md` § Assessment timers
**Stage:** Verifying — **Waiting to merge**
**Code:** worktree `.worktrees/time-clock-part-8`, branch `codex/time-clock-part-8` (pushed), claim
`b08a72aaec4e` (owner `claude-time-clock-p8`, kept until merge)
**Done when:** An Assessment timer lands once on Timesheets, never on a Job cost, and only today's
Assessments offer Start.

## Steps

- [x] Migration `20261211090000_assessment_timers` written, proven in a rolled-back transaction, **applied to
      the remote database and recorded** (do not re-apply). Types regenerated.
- [x] API: `POST /api/time-clock/timer` takes `{ assessment_id }`; Timesheets PATCH carries `request_id`;
      POST refuses it. Route and lib tests pass (`src/routes/api/time-clock`, `src/lib/time-clock`).
- [x] Screens coded (uncommitted until this checkpoint): `VisitTimerControl` renamed `WorkTimerControl`
      (visit or assessment target); Start/Stop on the Request page's assessment card (`AssessmentBlock`) and
      the Schedule's `AssessmentPreview`; header timer, Home day clock, Timesheets rows, entry list, entry
      dialog ("This assessment" choice), history and Approve list name Assessment time.
- [ ] `npm run check` — started, did not finish before the pause; run it and fix any errors.
- [ ] `npx prettier --check` on the changed files; `npx vitest run src/lib/time-clock src/routes/api/time-clock src/lib/components/jobs`.
- [ ] Live journey on the dev app at 1440px and 390px (design screen check, small change): Field member
      (`Login.md`) on a Request whose assessment is booked today and assigned to them → Start on the Request
      page and in the Schedule preview → header shows "Assessment" → Stop → Timesheets day shows
      "Assessment · <title>", no Job cost; tomorrow's assessment shows no Start; ticking "Assessment
      complete" while running stops it. Save screenshots and `live-journey.md` in the proof folder.
- [ ] Commit, merge to main per `docs/agent-concurrency.md`, mark roadmap Part 8 done, release the claim.

## Next

In the worktree, run `npm run check` (takes over 2 minutes; run it in the background), fix errors, then
do the live journey above. Test data has to be set up: an assessment booked for today, assigned to the
Field member, in Raad LTD (org `18f0d717-904e-48d8-bd99-9df7e3844cda`).

## Proof

- Database rules — `docs/research/time-clock-assessment-timers-2026-10-12/database-proof.sql` and
  `database-proof-output.txt`: today-only, assigned-only, one timer at a time, pauses and resumes the day
  clock, 40 minutes recorded once against its Request with no job entry, completion stops it, corrections
  keep or clear the Request and history names it.

## Notes

- Completing an Assessment stops its timers through a database trigger
  (`assessments_stop_timers_on_complete`), so the pipeline's "complete" path is covered too. This applies
  the plan's "like a visit timer"; tell Jafar in the report.
- Lists that show everyone's timers (Timesheets rows, Approve) say only "Assessment", never the Request's
  title, because the reader may not be allowed to open it. Entry lists and history show the title when the
  reader can open the Request.
