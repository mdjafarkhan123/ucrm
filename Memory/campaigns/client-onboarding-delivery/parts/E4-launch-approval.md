# E4 — Launch approval

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 6 (Jafar's choices, E4)
**Code:** `main`
**Done when:** Approval records version, person, and time.

## Steps

- [x] Jafar's choices recorded in plan §6
- [x] Migration `20261102090000_setup_launch_approvals.sql`: requests table, Jafar's ask / resend / record, client approve / not yet (signed in), link resolve / decide (service role), new release cancels or replaces, sent notes cancel an open ask, onboarding list next actions
- [x] Apply to dev (checked by a rolled-back trial of every command), regenerate types
- [ ] `$lib/setup/launch-approval.ts` (wording, states) + project-state `approved`; server reads and emails (link to approver, receipt to approver + owners/admins, in-app note to Jafar)
- [ ] Routes: Jafar ask/resend/record; client approve/not-yet; public `/launch/[token]` page + its API
- [ ] UI: Jafar's preview panel, client Setup page, public page
- [ ] Tests, full type check, browser check on Raad LTD, remove test data

## Next

Write `src/lib/setup/launch-approval.ts` and add `approved` to `src/lib/setup/project-state.ts` (step 4).

## Notes

- Approver = newest send's `business.approver_*` when given and `business.contact_is_approver` is not `yes`;
  otherwise the main contact. Raad LTD's send has no `contact_is_approver` (older questions).
- Ask only on the newest released version whose notes were not sent; sending notes cancels an open ask.
- The public page shows card titles, summaries and links, not screenshots (those need a signed-in route).
