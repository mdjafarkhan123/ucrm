# B3b.4 — feedback

**Stage:** Built and checked; waiting to merge. Branch `codex/classic-b3b4`, worktree
`/home/jafar/Ucrm/.worktrees/classic-b3b4`, reservation `0493f5153626`.

**Agreement:** B3b.1 Option A, approved 2026-10-15, saved `classic.pen` masters `WtnC7` (Banner),
`ym1rY` (Toast), `Uh8vP` (Tooltip). No new product behavior. Pencil live connection was unavailable;
read the saved masters directly. Reused existing Banner/Toast and installed Bits UI tooltip primitives.

**Built:** Classic-only banner cards with status icon tiles and optional title; compact toasts with inline
actions; reusable short hover/focus Tooltip in the previously empty file. Existing `InfoTip` remains a
click-open popover for longer explanations. Tooltip is demonstrated in the authenticated
`/dev-preview/feedback` harness; record-page callers can adopt it during their approved build parts.
Caller snippets and toast save/dismiss/pause behavior stay intact. Tooltip uses explicit accessible IDs
and child rendering because the installed floating content wrapper omitted its ID from the default DOM.

**Proof (2026-10-15):** Focused Prettier and ESLint pass; Svelte autofixer after SCSS preprocessing reports
no issues for all four touched components/pages. Browser preview at 1440, 1100 and 390, light/dark:
no horizontal overflow; success/error/loading feedback visible; Undo, dismiss, hover, focus and Escape pass;
tooltip's `aria-describedby` resolves to its content ID. Real `/settings/alerts` banner checked.
Real Botanical preview also checked: banner retains its borderless appearance, no Classic tokens are
present. The temporary preview server was stopped afterward to release memory.
Screenshots `/tmp/classic-feedback-*.png`; reproducible browser script `/tmp/classic-feedback-check.cjs`.
Full project check intentionally stopped at Jafar's request due its 4.2 GiB RAM use; do not rerun it for
this styling slice. Use focused checks. A pre-existing JobVisitsSection unused-selector warning is unrelated.

**Next:** Integrate once main is available. Main is held by `5a5e1549bc54` and contains other sessions'
uncommitted instructions/Memory changes; preserve those. Update `stages/shared-parts.md` B3b.4 and the
campaign checkpoint during integration, then release this claim. B3b.2/B3b.3 remain separate claimed parts.
