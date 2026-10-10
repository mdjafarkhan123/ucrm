# 1 — Complete job details demo

**Campaign:** uplift-design-refresh · **Plan:** `docs/uplift-design-refresh-behavior-contract.md` § First milestone
**Code:** `/tmp/ucrm-job-design`, branch `codex/job-design-concept`. Memory remains authoritative on main.
**Done when:** Coverage matches the current page; desktop/phone checks pass; demo is saved and Jafar approves.

## Steps

- [x] Preserve the approved visual direction and balanced typography.
- [x] Inspect current main page, nested sections/dialogs, navigation and read-only live Job #1.
- [x] Complete missing sections, action previews and mutually exclusive scenarios.
- [x] Check desktop/phone, keyboard, dialogs, staging and coverage; save the demo remotely.
- [ ] Jafar approves appearance and completeness, reviewing small pieces first.

## Next

Jafar selected Botanical v3 and requested moving only that existing demo into the app. The canonical visual reference is now `/demo/job-details`, in `static/demo/job-details/` on main. Its README explains maintenance and limitations. The existing `/demo` component index is preserved. No real job page, design skill, API, schema, or provider behavior was changed.

Use the selected v3 for appearance and readable typography. Jafar wants small pieces reviewed one at a time and explicitly said not to load the current design skill. The selected preview has simplified title/instructions and photo dialogs, while many commands remain preview notices. Full interaction/scenario coverage is still pending; appearance selection does not complete the milestone.

The deeper earlier prototype remains in branch `codex/job-design-concept`, `/tmp/ucrm-job-design/design-previews/job-details/`. Its `coverage.md` and `verify.cjs` describe the behavior work available to migrate in focused pieces. Its three-column finance grid is not the selected layout.

## Approval boundary

No design-system extraction, skill rewrite, other page layouts or real-app rollout before Jafar’s approval. Keep the existing preview worktree until approved integration, then remove it. Preserve the other session’s main-worktree changes.
