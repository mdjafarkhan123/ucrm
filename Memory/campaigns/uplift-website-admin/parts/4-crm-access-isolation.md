# Part 4 — CRM access and isolation

**Campaign:** `uplift-website-admin` · **Plan:** `docs/plans/uplift-website-admin.md` § Product boundary
**Code:** worktree `.claude/worktrees/cms-planning-update`, branch `cms-planning-update`; integrate plan and Memory into `main` before closing
**Done when:** The access contract and failure behavior are approved.

## Steps

- [x] Inspect the existing CRM authentication, organization, and owner-role implementation read-only.
- [x] Research CRM-native entry, site selection, and tenant-isolation patterns.
- [x] Replace separate-CMS handoff and one-site assumptions; record setup-before-assignment and named multi-site selection.
- [ ] Set exact setup milestones, no-website-package state, and who can view the Website area.
- [x] Set owner-role change, site unassignment, and logout behavior under the existing CRM session.
- [x] Set server and database isolation guarantees and denied-access screens.
- [ ] Record the approved access contract in the plan.

## Next

Integrate this branch into `main` now that the pipeline claim is released. Then settle the three owner-visible setup/access questions below and record them in `docs/plans/uplift-website-admin.md` before closing Part 4.

## Notes

This work is now inside UCRM. Superseded handoff research remains in `docs/research/uplift-cms-crm-owner-handoff-2026-10-02.md`; current patterns are in `docs/research/uplift-crm-website-area-patterns-2026-10-02.md`. The CRM allows one organization per user and one owner per organization, re-queries active membership, and atomically demotes the old owner during ownership transfer. It has no site-assignment model yet.

Questions waiting for Jafar:

- **Q14 — Setup progress:** Which milestones are truthful and useful before a site is assigned? Recommendation: show the existing onboarding delivery stages, the next action, and a support link; do not imply a site is ready just because the organization exists.
- **Package boundary:** The approved package plan distinguishes a managed website service from CRM access. Decide the Website area's state for an organization whose package does not include a website; setup progress applies only when the service is included.
- **Q15 — Visibility:** May teammates see read-only setup/site status, or should the whole Website area be owner-only? Recommendation: owner-only for V1 to keep private drafts and launch approval clear.
Settled for Part 3B: Jafar approved that the named final approver may approve first launch even when they are not the CRM owner; this grants no editing or publishing access. The plan records the approver, version, and time.
