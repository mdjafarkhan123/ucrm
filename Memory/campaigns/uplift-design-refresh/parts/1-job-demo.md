# 1 — Complete job details demo

**Campaign:** uplift-design-refresh · **Plan:** `docs/uplift-design-refresh-behavior-contract.md` § First milestone: complete job details demo
**Code:** Worktree `/tmp/ucrm-job-design`, branch `codex/job-design-concept`. Memory is authoritative only in `/home/jafar/Ucrm` on `main`.
**Done when:** Coverage matches the existing page; desktop/phone checks pass; demo is saved and Jafar approves it.

## Steps

- [x] Preserve the approved visual direction and balanced font sizes on the preview branch.
- [x] Initial source inspection identified the major missing sections; this is not a complete coverage audit.
- [ ] Read the Jobs contract and inspect the live page plus nested components, sidebar, and header. Produce the section/action/state/permission checklist.
- [ ] Complete the demo against that checklist, preserving the approved aesthetic.
- [ ] Implement temporary preview interactions and mutually exclusive scenarios.
- [ ] Check desktop, phone, keyboard, dialogs, editing, and coverage; commit and push the demo.
- [ ] Present the complete demo for Jafar's appearance and completeness approval.

## Next

Run the live register and claim this part in the preview worktree. Inspect `git status` and `git diff` before editing. The stopped session added an uncommitted scenario toolbar, edit bar, dialog, and `demo.js` reference to `design-previews/job-details/index.html`; `demo.js` does not exist yet. Its unfinished changes are authorized for takeover. Finish the inventory before implementing the missing sections. Do not infer completeness from the partial markup.

Read `src/routes/(app)/jobs/[id=uuid]/+page.svelte` in the current main application and follow its imported job/shared components. Consult `docs/jobs-behavior-contract.md` and use `Login.md` for read-only live observation. Use the main application's current behavior rather than assuming the older preview checkout has all recent changes.

## Notes

Jafar explicitly requested this session create only the campaign. No missing sections were completed during setup. Complete the demo and obtain his approval before extracting the design system or rewriting the design skill. Pencil is omitted. The local demo was served at port 4187; verify the server and URL before reporting it live. Preserve unrelated main-worktree edits from the platform campaign. Keep this preview branch isolated until its approved integration; do not leave a second product copy after integration.
