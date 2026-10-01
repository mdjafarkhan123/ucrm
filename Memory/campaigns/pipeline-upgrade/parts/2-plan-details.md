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

❓ **Q7 — Stage administration:** Should we allow up to 25 custom stages, require unique names inside each
Request/Quote section, use Disable as the normal removal action, relocate active cards safely, and retain every
used stage in history instead of physically erasing it?

➡️ Yes.

❓ **Q8 — On hold:** When a customer says “call me next month,” should the card stay Open in an On hold custom
stage, require a future Task, pause inactivity only until that Task is due, and never count as Lost?

➡️ Yes.

❓ **Q9 — Honest sending:** Should queue acceptance or a deliberate external mark-sent action move the Quote to
Awaiting response; immediate failure keep it Draft; later delivery failure remain visible with an alert; and
external mark-sent record actor, time, channel, and optional note?

➡️ Yes.

❓ **Q10 — Attention rules:** Should defaults be New 1 day, Assessment 2, Draft 2, Awaiting response 5, and
Changes requested 2; reset only for meaningful customer/work progress; and notify once when another teammate is
assigned or reassigned a Task?

➡️ Yes.

❓ **Q11 — Honest reports:** Should outcome lists use outcome date; funnels use created cohorts and show Open
separately; Request-to-Quote, Request-to-Won, and per-Quote win rates stay distinct; Direct jobs stay separate;
and days to win show both median and average without fake zero values?

➡️ Yes.

❓ **Q12 — Views and bulk work:** Should saved filters be personal with admin-shared options; table and mobile
compact-list views ship; bulk actions be limited to owner, Task, and custom-stage changes; and accessible Load
more remain until a prototype and load check prove a better lane-loading model?

➡️ Yes.
