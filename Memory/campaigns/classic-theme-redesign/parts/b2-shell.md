# B2 — Classic sidebar and top bar

**Stage:** Build in progress; waiting to merge. **Approval:** B2 order and Classic Pencil screens approved 2026-10-13. **Branch:** `codex/classic-b2`; **worktree:** `/home/jafar/Ucrm/.worktrees/classic-b2`. **Reservation:** `c59bd0b6a913` (release after this explicit handoff). Jafar asked to pause for a new session on 2026-10-14.

## Built in this checkpoint

`ClassicFrame`, `ClassicHeader` and `Sidebar` use the approved `classic2-*` palette, 248px black-green sidebar, 76px collapsed state, page background, 44px header controls and responsive search. Classic hides the four Soon entries; Botanical's sidebar/header remain separate. `Topbar` keeps Botanical's avatar icon while showing initials in Classic when no photo exists, and labels icon-only Add new for screen readers. The Classic sidebar guidance now points to these values.

## Evidence and limits

`npm run build` passed (42.45s). Prettier and `git diff --check` passed. Svelte autofixer found no issues in the changed frame/header/Topbar; its Sidebar `&__` warnings are SCSS parser false positives and the production build compiles it. `SharedAppShell` has pre-existing effect suggestions. Full `npm run check` consumed ~4.9 GB and remained busy after four minutes, so it was stopped, consistent with B1's noted heap issue.

Live Playwright on the branch dev server: contractor Dashboard and Settings at 1440px/390px, light/dark; owner Control Room at 1440px; collapsed sidebar, phone drawer, Escape/focus return. These showed no horizontal overflow or browser page errors. `Soon` labels were absent. Screenshots are in `/tmp/classic-b2/` on this machine. A phone axe pass found Add new's missing name; it was fixed. Sign-ins later became intermittent and prevented the final Botanical preview and control recheck. The live Settings page still has its old body layout; its redesign belongs to later parts. The existing Add new menu still says “Nothing to create yet”; B2 did not invent creation actions.

## Next

1. Compare Botanical screenshot in private `DESIGN_SHELL_PREVIEW=botanical` with B1's baseline, using a fresh working contractor session. Confirm shared Topbar's hidden initials and search wording have no Botanical visual change.
2. Recheck Classic at 1440px/390px after the final CSS edit: desktop/phone light and dark, long organization name, enlarged text, drawer, account, search and notifications. Run axe again for changed controls. Fix any issue found. Keep the approved page shell; no new Pencil approval is needed.
3. Decide the approved Settings search addition's build part from the first-version plan; it is not in the current search dialog yet. Record its owner before marking the first version done.
4. Commit proof, update this stage and NOW, push branch, then integrate into clean main under a separate `main-integration` claim. Run combined checks, push main and release reservations.
