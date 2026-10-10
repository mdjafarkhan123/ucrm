# 6 — Job follow-up

**Campaign:** client-reminders · **Plan:** `docs/client-reminders-behavior-contract.md` § Job follow-up, § Customer messages: shared rules
**Code:** worktree `/home/jafar/Ucrm-cr6`, branch `client-reminders-6`
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
- [ ] Prove on the live app; merge to `main`; remove worktree

## Next

Prove on the live app: turn on Job follow-up, close a one-off job for a client with an email, see one thank-you in the client history; then merge to `main`, remove worktree.
