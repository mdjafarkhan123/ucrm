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

Jafar’s latest instruction: “Dont buiild all layout at once.” Stop adding layouts. Show the current demo for a small review starting with sidebar/header; wait for feedback before further design work. The complete job demo is prepared, but neither this milestone nor later extraction is approved.

Preview URL: `http://localhost:4187`. Check that the server runs; serve `design-previews/job-details/` on port 4187 if needed. `README.md` explains the controls; `coverage.md` maps current capabilities, evidence, primary research sources and limitations. `verify.cjs` repeats the browser checks.

Jafar also clarified that all UI/UX design must be research-based. The coverage file separates proven workflow/accessibility patterns from our visual adaptations. Section editors are simulated previews, not a second business engine. Local illustrated photo samples are labelled. No real app, design skill, API, schema or provider changes were made.

## Approval boundary

No design-system extraction, skill rewrite, other page layouts or real-app rollout before Jafar’s approval. Keep the existing preview worktree until approved integration, then remove it. Preserve the other session’s main-worktree changes.
