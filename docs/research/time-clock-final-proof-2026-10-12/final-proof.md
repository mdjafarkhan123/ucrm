# Time clock Part 9 — final proof (2026-10-12)

Every success check in `docs/time-clock-behavior-contract.md` § Success checks, run on the live dev app (branch
dev server, remote dev database, Raad LTD) with real logins from Login.md: the contractor owner (manager) and
the Field member (timers only). Script: `final-proof.mjs` (35 checks, 35 pass; results in
`final-proof-results.json`). Screenshots in this folder.

| # | Success check | Result |
| --- | --- | --- |
| 1 | Start on today's visit, stop 40 minutes later → one 40-minute entry in the Job's Labor at their rate; Timesheets day shows the same 40 | Pass — 40 min, rate 3000 → cost 2000; on screen at 390px (`1-job-labor-390.png`, `1-timesheets-day-390.png`). The 40 minutes are a timer backdated in SQL; a real wait would be 40 minutes. |
| 2 | Clock in, visit, stop, clock out → General + visit hours, no overlap | Pass at one minute per hour in real time: 1 + 2 + 1 minutes, contiguous, Timesheets flags no overlap. The 8:00-12:00 arithmetic itself was proven in Part 3's rolled-back database run. |
| 3 | Stop twice or on two devices → recorded once | Pass — two sessions stopped at the same moment plus a third Stop: three 200s, one entry |
| 4 | Complete a visit with its timer running → timer stops, hours land once | Pass — 7 minutes, one entry, no running timer left |
| 5 | Left running overnight → manager sees the warning, stops it at 5:30 pm the day before, history shows who | Pass — over-24-hour warning flagged, the crew member's own Stop refused (409), the manager's stop-at gives 08:00-17:30 (570 min) on the starting day, history names the manager (`5-manager-warning-1440.png`, `5-stopped-day-before-1440.png`). The long timer is a timer backdated in SQL. |
| 6 | Timers only → can start and stop, cannot add, change or delete, on screen and through `/api` | Pass — add, change and delete all 403; on screen no Add button and the entry menu offers History only (`6-timers-only-menu-390.png`) |
| 7 | Manager approves → crew member cannot change those entries; manager still can; history records it | Pass — approved 570 min; with "own hours" granted for the run the crew member gets 409 on change and delete; manager change 200 and the entry stays approved; history shows approval and the change |
| 8 | Without "anyone's hours" → cannot see or change a teammate's entries, including through `/api` | Pass — Timesheets lists only themselves; reading, changing, deleting, reading history of the owner's entry, and approving are all refused (403/404) |
| 9 | Week view speed measured on a 15-person team's full week | Done in Part 4: 1,260 entries, summary 24 ms, page no slower than Jobs on a throttled phone (`docs/research/time-clock-timesheets-2026-10-11/performance-results.md`). Not re-measured. |

Other parts' live proof stays where it was recorded: Assessment timers (Part 8), approval (Part 7), timers-only
(Part 6), corrections (Part 5).

## Screen check (Classic)

Screenshots read cleanly at 390px and 1440px: the manager's warning bar and the "Over 12 hours" badge, the Labor
list, and the entry menu. The header's "Nothing to create yet" popover opens by itself on a phone at page load and
can cover the page until closed; it is not a time-clock screen (noted for the design campaign).

## Test data left in Raad LTD

Field Tester has approved entries on 11 Oct (an 08:00-17:30 General entry) that overlap other test entries, so
Timesheets shows overlap warnings for them; a handful of 12 Oct entries from the runs; Job #20 has three
"Final proof" visits. The temporary cost rate, the temporary own-hours override and the owner's test entry were
removed at the end of the run.
