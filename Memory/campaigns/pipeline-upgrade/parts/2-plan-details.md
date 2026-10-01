# 2 — Plan: details

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` § Still unclear
**Code:** `main` (planning only — no code)
**Done when:** Still unclear is empty and Jafar approves revision 3

## Steps

- [x] Record Jafar's approval of the corrected round-1 foundation
- [x] Ask round 2 detail questions, 2026-10-01
- [x] Write Jafar's answers into the plan, 2026-10-01
- [ ] Ask any dependent final details and obtain revision-3 approval

## Next

Wait for Jafar's answers to Q13–Q17 below. Then write them into the plan, confirm that **Still unclear** is
empty, and ask for revision-3 approval.

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

❓ **Q13 — Honest Quote endings:** Jobber does not call a never-sent Draft a lost sale. Should archiving such a
Draft remove it from the board as **abandoned before sending**, exclude it from Lost reasons and Quote win-rate
math, and retain its audit history; while a customer-declined sent Quote becomes Lost, lets the customer leave
an optional message, and lets staff classify the internal Lost reason afterward?

➡️ Recommended: Yes.

❓ **Q14 — Meaningful inactivity:** Should only real progress reset the warning—customer reply, successful or
externally confirmed send, explicitly logged call outcome, Task completion, assessment schedule/completion,
Quote revision/send, or another protected domain action—while owner/value/date edits, internal Notes, Task
creation/reassignment, and manual custom-stage shuffling do not reset it?

➡️ Recommended: Yes. This prevents staff from making an ignored customer look active through housekeeping.

❓ **Q15 — Honest report value:** Should Won value be frozen from the accepted Quote total or the Job total at
the moment a direct Request/Direct job becomes Won; Lost value be frozen from the last sent Quote total or
the Opportunity value recorded on a Request at loss; later document edits not rewrite old outcomes; and missing
values stay **Unvalued** rather than zero?

➡️ Recommended: Yes.

❓ **Q16 — Search and contact actions:** Should Pipeline search cover client/contact name, title, Request/Quote
number, service address, phone, and email—but not Notes, file contents, or custom fields at launch; and should
Email/Text open the existing Communications composer, multiple details open a chooser, and Call open the
device dialler with an optional return note instead of pretending the call was logged automatically?

➡️ Recommended: Yes.

❓ **Q17 — Assignment alerts:** Should assigning or reassigning a Task to someone else create one in-app alert,
use email or mobile/browser push only according to that teammate's preferences, avoid notifying a person about
their own assignment, and never notify the customer?

➡️ Recommended: Yes.
