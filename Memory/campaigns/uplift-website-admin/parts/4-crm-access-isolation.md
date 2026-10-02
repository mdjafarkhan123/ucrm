# Part 4 — CRM access and isolation

**Campaign:** `uplift-website-admin` · **Plan:** `docs/plans/uplift-website-admin.md` § Product boundary
**Code:** `main`
**Done when:** The access contract and failure behavior are approved.

## Steps

- [x] Inspect the existing CRM authentication, organization, and owner-role implementation read-only.
- [x] Research CRM-native entry, site selection, and tenant-isolation patterns.
- [x] Replace separate-CMS handoff and one-site assumptions; record setup-before-assignment and named multi-site selection.
- [ ] Set exact setup milestones, no-website-package state, and teammate view/edit/publish permissions.
- [x] Set owner-role change, site unassignment, and logout behavior under the existing CRM session.
- [x] Set server and database isolation guarantees and denied-access screens.
- [ ] Record the approved access contract in the plan.

## Next

Wait for Jafar's answers below, then record the approved access contract in `docs/plans/uplift-website-admin.md`.

## Notes

The approved onboarding contract §5 already names eleven delivery states, including **Building your system**, **Ready for your review**, and **Approved — preparing launch**. The package plan separates a managed website service from CRM access. The CRM has one active owner per organization and no site-assignment model yet. Current research: `docs/research/uplift-crm-website-area-patterns-2026-10-02.md`.

## Questions waiting for Jafar

1. **What should the Website area show while Uplift builds a purchased site?** I recommend the site’s current step using the already approved delivery stages, the next action the contractor can take, any named blocker, and a link to ask Uplift. It should never say a site is ready before Uplift assigns one. Choices: Show real progress and next action (recommended); Show only a coming-soon message; Hide Website until assignment.
2. **What should a CRM customer see if their package has no managed website?** I recommend a simple Website page saying the service is not included, with a Contact Uplift action. It should show no editor or fake setup progress. Choices: Show explanation + contact Uplift (recommended); Hide Website entirely; Show upgrade button.
3. **Which website access can the CRM owner give teammates?** I recommend three choices per teammate: View (site and progress), Edit (draft content and preview), and Publish (make later changes live). Edit includes View; Publish includes Edit. The owner keeps full access. A first launch still needs its separate named approver. Choices: View, Edit, Publish (recommended); Edit and Publish only; One all-access permission.
