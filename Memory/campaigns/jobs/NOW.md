# Jobs: Current Checkpoint

- Goal: Build simpler contractor Jobs and Visits without losing proven Jobber behavior.
- State: Parts 1–11b, 13a, 14a–14e, 15a-1, 15a-2 complete. 15a-3 and 15a-4 are behaviourally complete,
  applied, measured and committed (`c6b2474`); both still owe one browser check. 11c/12/13b belong to
  Invoices and Schedule.
- Contract: `docs/jobs-behavior-contract.md` — still not updated for 15a-2, 15a-3 or 15a-4. Update it once,
  for all three together, right after the browser check.

## Next action

Read `parts/15a-4.md` § "The exact next action". In short: run the app, sign in as the Field member
(`dev.jafarkhan@gmail.com`) and confirm the Schedule shows only their own week with no team controls and
reads "My Schedule"; sign in as the contractor owner (`info.socialmediauser1@gmail.com`) and confirm the
Schedule, Jobs list and job detail are unchanged. Then update the behaviour contract for 15a-2, 15a-3 and
15a-4 together, and 15a closes.

Nothing here needs Jafar first. After 15a, the next roadmap part is 15b (internal Job/Visit notes, files and
photos).

## Deliberately deferred, not silently dropped

- The clients family still evaluates `can_view_client` once per row — the same defect 15a-4 fixed for jobs,
  same fix, left alone to keep that change to one family. Details in `parts/15a-4.md`.
- Photo category labels: cut by "follow Jobber" — Jobber has no such field. May return as our own
  differentiator; nothing in 15a blocks it.
- Jobber's profit alerts; the item-cost/expense double-count case; standalone non-Job expenses; the standalone
  "Close Job" button with its incomplete-visit preview; wiring Upcoming/Today/Late/Action required into
  `private.job_derived_status` / `job_list_rows` / `job_status_count_rows`; per-entry labor rate overrides;
  a start/stop timer and a company-wide Timesheets page.

Resume command: `read memory and continue the Jobs campaign`.
