# Part 3B — first launch

**Campaign:** `uplift-website-admin` · **Plan:** `docs/plans/uplift-website-admin.md` § Preview and publishing
**Code:** `main`
**Done when:** First-launch states and revision path are approved.

## Steps

- [x] Confirm Uplift checks the first site and records contractor approval before it goes live.
- [x] Confirm the named final approver may differ from the CRM owner without gaining edit or publish rights.
- [x] Read the existing onboarding review and launch rules and the CMS release research.
- [x] Record the existing check, exact-version preview, correction, approval, and go-live rules.
- [ ] Set the site-level review states and withdrawal behavior; decide a secure approval path for a named approver without a CRM account.
- [ ] Record the approved first-launch flow in the plan and reconcile it with onboarding.

## Next

Wait for Jafar's answers to the three questions below. Then settle the site-level states, record the approved flow in the plan, and reconcile the onboarding contract.

## Questions waiting for Jafar

1. **How should a named approver without a CRM account approve a site?** I recommend a private email review link, followed by a one-time code sent to that same address before they approve or request changes. The link shows only the fixed website preview and the decision buttons; it never opens the editor. Choices: Private link + email code (recommended); Require a CRM account; Uplift records approval manually.
2. **What if the approver changes their mind after approving but before the site goes live?** I recommend a Withdraw approval action in the same review view. It immediately stops the launch. Uplift must present a fixed version for approval again before going live. Choices: Allow withdrawal until live (recommended); Contact Uplift to withdraw; Approval cannot be withdrawn.
3. **After the site is live, should the same approval page offer a way to take it down?** I recommend it should show that the approved version is live and direct the approver to Uplift for a takedown or correction. Taking down a live site needs a separate confirmed action because customers may already be using it. Choices: Contact Uplift after launch (recommended); Approver can take site down; Owner can take site down.

## Notes

The onboarding contract requires Uplift's cross-service check, an organized preview, one factual-correction round, and explicit approval with version, approver, and time. Its setup catalogue collects `business.approver_name` and `business.approver_email`. The CRM has no separate CMS login. Account-free review is researched in `docs/research/uplift-crm-website-area-patterns-2026-10-02.md`.

Proposed per-site states: **Uplift preparing → Uplift checking → Ready for review → Changes requested → Approved, preparing launch → Live**. Later assigned sites repeat these without reopening organization onboarding. These states and the review path remain proposals until Jafar answers.
