# Part 3B — first launch

**Campaign:** `uplift-website-admin` · **Plan:** `docs/plans/uplift-website-admin.md` § Preview and publishing
**Code:** worktree `.claude/worktrees/cms-planning-update`, branch `cms-planning-update`
**Done when:** First-launch states and revision path are approved.

## Steps

- [x] Confirm Uplift checks the first site and records contractor approval before it goes live.
- [x] Confirm the named final approver may differ from the CRM owner without gaining edit or publish rights.
- [x] Read the existing onboarding review and launch rules and the CMS release research.
- [x] Record the existing check, exact-version preview, correction, approval, and go-live rules.
- [ ] Set the site-level review states and withdrawal behavior; decide a secure approval path for a named approver without a CRM account.
- [ ] Record the approved first-launch flow in the plan and reconcile it with onboarding.

## Next

Review the proposed site-level states below against the plan's first-launch section. Decide withdrawal and how a named non-owner approver can review and approve without entering the owner-only editor. Integrate the branch into `main` when its write claim is free.

## Notes

The current onboarding contract already requires Uplift's cross-service prelaunch check, an organized preview, one factual-correction round, and an explicit final approval recording approved version, approver, and time. It does not yet define the approval interface or identity check for a named approver who lacks a CRM user account. The Website area uses the contractor's CRM login and has no separate CMS login.

Proposed per-site states: **Uplift preparing → Uplift checking → Ready for review → Changes requested → Approved, preparing launch → Live**. A site added after the first delivery uses these states without reopening organization onboarding. If approval is withdrawn before promotion, stop launch and return to review; after a site is live, a new decision cannot silently undo a live release. Check any removal or rollback with Uplift.
