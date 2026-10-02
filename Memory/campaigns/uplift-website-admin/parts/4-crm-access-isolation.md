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

Settle the remaining setup and teammate-permission questions below and record them in `docs/plans/uplift-website-admin.md` before closing Part 4.

## Notes

This work is now inside UCRM. Superseded handoff research remains in `docs/research/uplift-cms-crm-owner-handoff-2026-10-02.md`; current patterns are in `docs/research/uplift-crm-website-area-patterns-2026-10-02.md`. The CRM allows one organization per user and one owner per organization, re-queries active membership, and atomically demotes the old owner during ownership transfer. It has no site-assignment model yet.

Questions waiting for Jafar:

- **Q14 — Setup progress:** Which milestones are truthful and useful before a site is assigned? Recommendation: show the existing onboarding delivery stages, the next action, and a support link; do not imply a site is ready just because the organization exists.
- **Package boundary:** The approved package plan distinguishes a managed website service from CRM access. Decide the Website area's state for an organization whose package does not include a website; setup progress applies only when the service is included.
- **Q15 — Teammate permissions:** Jafar decided the owner has access by default and controls teammate access. Decide the exact view, edit, and publish choices, including whether a teammate can see setup/site status without edit permission.
Settled for Part 3B: Jafar approved that the named final approver may approve first launch even when they are not the CRM owner; this grants no editing or publishing access. The plan records the approver, version, and time.
Settled publishing boundary: Jafar already hosts Git-based Astro sites on Cloudflare. Publishing from CRM must update Uplift's private Git source and use that existing build/deploy path; contractors have no Git or source-file access. `docs/plans/uplift-website-admin.md` records this choice. Part 7 must confirm exact preview, branch, deployment-status, and rollback mechanics against the actual site.
