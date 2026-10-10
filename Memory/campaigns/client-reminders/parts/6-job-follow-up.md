# 6 — Job follow-up

**Campaign:** client-reminders · **Plan:** `docs/client-reminders-behavior-contract.md` § Job follow-up, § Customer messages: shared rules
**Code:** on `main` (merged 2026-10-10; worktree removed)
**Done when:** Closing a job sends one thank-you only when the client's switch is on.

## Design (technical, chosen 2026-10-10; mirrors Parts 3 and 5)

- Reuses trigger `job.work_completed` (already used by the Google review ask). New action
  `action.send_job_email` (variables: customer, business, job title). Preset "Job follow-up": trigger, one email,
  no wait (owner may add one). A recipe may not mix a review ask and a thank-you.
- Which client switch applies is chosen by the recipe's action: a thank-you follows `job_follow_ups` (+ Do not
  disturb), a review ask keeps `review_requests`. Intake and advance pick per recipe; the existing always-on stop
  `stop.client_review_opt_out` is relabelled "The client turned off this message".
- Sending hours: the email effect waits until the business is next open (`organization_business_hours`); no hours
  set means send at once.
- Client screen: the job follow-up switch says "Not sending" unless an active `job.work_completed` recipe has the
  thank-you step.
- Never twice: existing job re-entry key (one per job; recurring per completed-visit count) + send key.

## Steps

- [x] Migration `20261118090000_job_follow_up.sql` written on the branch
- [x] Catalog, validator, email variables, preset, worker, builder, client switch status
- [x] Unit tests; `npm run check` clean (on the branch)
- [x] Migration `20261118090000` applied 2026-10-10
- [x] Merged to `main`; worktree removed
- [ ] Prove on the live app

## Next

Live proof, half done 2026-10-10 07:08 Dhaka: Jafar turned on "Job follow-up" (recipe 04201c7e-79a0-4e67-aa43-0003bc387160)
and Claude finished job #28 (visit marked complete, then Finish job). Result: one enrollment, one work item
waiting until 03:00 UTC (9:00 Dhaka) — the opening-hours wait works.

Still to check after 03:00 UTC: the work item is sent, the client's history shows one thank-you, the +part8 inbox
has it. Then reopen job #28, finish it again, and confirm no second email. Then tick the last step, release the
claim (`sonnet-cr-6`, read mode), and mark Part 6 done in ROADMAP.md/NOW.md.
