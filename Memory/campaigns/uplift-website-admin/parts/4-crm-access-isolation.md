# Part 4 — CRM access and isolation

**Campaign:** `uplift-website-admin` · **Plan:** `docs/plans/uplift-website-admin.md` § Product boundary
**Code:** worktree `.claude/worktrees/cms-planning-update`, branch `cms-planning-update`; integrate plan and Memory into `main` before closing
**Done when:** The access contract and failure behavior are approved.

## Steps

- [x] Inspect the existing CRM authentication, organization, and owner-role implementation read-only.
- [x] Research CRM-native entry, site selection, and tenant-isolation patterns.
- [x] Replace separate-CMS handoff and one-site assumptions; record setup-before-assignment and named multi-site selection.
- [ ] Set exact setup milestones and who can view the Website area.
- [ ] Set owner-role change, site unassignment, and logout behavior under the existing CRM session.
- [ ] Set server and database isolation guarantees and denied-access screens.
- [ ] Record the approved access contract in the plan.

## Next

Ask Jafar the access and setup questions below; record answers in `docs/plans/uplift-website-admin.md`. Recheck the current CRM session and owner on each protected action. Integrate this branch into `main` with the campaign entry before closing the part.

## Notes

This work is now inside UCRM. Superseded handoff research remains in `docs/research/uplift-cms-crm-owner-handoff-2026-10-02.md`; current patterns are in `docs/research/uplift-crm-website-area-patterns-2026-10-02.md`. The CRM allows one organization per user and one owner per organization, re-queries active membership, and atomically demotes the old owner during ownership transfer. It has no site-assignment model yet.

Questions waiting for Jafar:

- **Q14 — Setup progress:** Which milestones are truthful and useful before a site is assigned? Recommendation: show the existing onboarding delivery stages, the next action, and a support link; do not imply a site is ready just because the organization exists.
- **Package boundary:** The approved package plan distinguishes a managed website service from CRM access. Decide the Website area's state for an organization whose package does not include a website; setup progress applies only when the service is included.
- **Q15 — Visibility:** May teammates see read-only setup/site status, or should the whole Website area be owner-only? Recommendation: owner-only for V1 to keep private drafts and launch approval clear.
- **Q16 — Ownership or assignment changes:** Recommendation: deny the former owner or unassigned site on the next request; stop saves and publishing, preserve recoverable drafts, and show a plain access-changed screen.
- **Q17 — Wrong or guessed site address:** Recommendation: show **Website unavailable** without revealing another organization's site or status.
- **Q18 — Logout:** Use the CRM's existing session behavior. Its current sign-out is global across devices; changing that is a separate CRM-wide decision, not a CMS-specific login flow.
- **Part 3B overlap:** `docs/client-onboarding-delivery-behavior-contract.md` § 6 already records a named final approver, approved version, approver, and time. Ask whether that person may approve the website's first launch when they are not the CRM owner; editing and later publishing remain owner-only.
