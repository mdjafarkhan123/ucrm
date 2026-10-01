# 2 — Plan: details

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` § Still unclear
**Code:** `main` (planning only — no code)
**Done when:** Still unclear is empty and Jafar approves revision 3

## Steps

- [x] Record Jafar's approval of the corrected round-1 foundation
- [x] Ask round 2 detail questions, 2026-10-01
- [ ] Write Jafar's answers into the plan
- [ ] Ask any dependent final details and obtain revision-3 approval

## Next

Wait for Jafar's answers to Q7–Q12 below, then update the plan and recompute the decision frontier.

## Notes

Q7 — Stage administration: maximum 25 custom stages; unique names within Request/Quote; disable is normal;
removal moves active cards within the same section and preserves immutable history; used stages are retired,
not physically erased.

Q8 — On hold: it remains Open in a custom follow-up stage, requires a future Task, and suppresses inactivity
only until that Task is due; it is never counted as Lost.

Q9 — Send truth: queue acceptance or deliberate external mark-sent moves to Awaiting response; immediate queue
failure stays Draft; later delivery failure stays Awaiting response with a visible failure/alert; retries are
idempotent; external mark records actor, time, channel, and optional note.

Q10 — Attention: defaults New 1 day, Assessment 2, Draft 2, Awaiting response 5, Changes requested 2. Only
customer contact, completed follow-up, stage progress, assessment, or quote work resets inactivity; internal
edits do not. Notify once when another teammate receives/re-receives a Task.

Q11 — Reports: outcome lists use outcome date; funnels use created cohorts and show Open separately; report
Request-to-any-Quote, Request-to-Won, and per-Quote win rates separately; Direct jobs remain separate; days to
win show median and average; value comes from accepted Quote or initial Direct-job value, never fake zero.

Q12 — Views and bulk work: personal saved filters plus admin-shared views; table and mobile compact-list views;
bulk owner, Task, and custom-stage actions only; no bulk sending, conversion, protected-stage move, or Lost;
keep accessible Load more until a prototype and load check prove a lane-loading replacement.
