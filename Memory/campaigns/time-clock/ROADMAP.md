# Time clock — roadmap

**Plan:** `docs/time-clock-behavior-contract.md` — parts 2–8 are a proposed split, not yet approved.

| Part | Plan section | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- | --- |
| 1 Plan | whole plan | Answers to choices 1–5; approved first-version scope and build order | — | Still unclear has no first-version question; Jafar approved scope and parts | In progress |
| 2 Visit timer | § Timers, § Hours on the Job | Start and Stop on a visit from Schedule and Job; one timer at a time; completing a visit stops it; hours land once on Job Labor with a running mark | 1 | On the live app at phone width: start, stop and complete each land one entry at the right rate; double Stop stays one entry; another person cannot stop it | Not started |
| 3 Day clock | § Timers | Clock in and out from Home; the visit timer pauses and resumes general time; running timer shown on every page | 2; header free from `selectable-design-experiences` Part 4 | The 8:00–12:00 success check passes on the live app | Not started |
| 4 Timesheets page | § Timesheets page, § Permissions | Day and Week views, own vs everyone, filter, add/edit/delete, history, manager clock in/out and stop, warnings | 3; sidebar free from `selectable-design-experiences` Part 4 | Own-only and manager logins see the right rows; edits show history; running-timer limits hold; performance review measured | Not started |
| 5 Timers-only permission | § Permissions, choice 1 | The lowest rung in Team access; Field preset moved, if approved | 4; choice 1 | A timers-only login can start and stop but not add or edit, in the screen and through `/api` | Not started |
| 6 Weekly approval | choice 2 | Approve hours up to a date for chosen people; lock with manager exception, if approved | 4; choice 2 | Approved entries refuse changes from own-only logins and accept them from managers, with history | Not started |
| 7 Assessment timers | choice 5 | Start and Stop on today's Assessment; hours on the timesheet against its Request, if approved | 3; choice 5 | An Assessment timer lands once on the timesheet and pauses the day clock | Not started |
| 8 Final proof | § Success checks | Every success check on the live app with each role login; design screen check | 2–7 as approved | All success checks pass with evidence recorded | Not started |
