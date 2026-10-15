# Approved replan — handover

**State:** Waiting to merge. Jafar approved the whole-application Classic redesign and staged design/build loop on 2026-10-15. This planning session is finished; the campaign continues.

**Saved work:** Branch `codex/classic-redesign-approved-plan`, pushed to origin, in `/home/jafar/.codex/worktrees/classic-redesign-plan/Ucrm`. Its head before this handover was `3591efe8`. It starts from `codex/b4-save-bar-integration` because B4 integration was pending. Reservation `a12762937bd0` (`approved-replan`) is released after this handover is pushed. The worktree is kept for the next session.

**What is saved:** Whole-app scope and new-concept target, the approved stage order, the B3b shared-parts inventory, normative behavior rules, and a Campaign Memory rule that makes agents read the campaign's core agreement on every resume. No application code or Pencil design was changed in this branch.

**Checks:** Prettier on edited Markdown, `git diff --check`, and the `NOW.md` link, anchor and word-limit checks passed. All branch commits were pushed. Main does not yet contain these changes.

**Next:** Check the reservation register and current main. Wait until the B4 integration owner finishes and releases `main-integration`. Claim this remaining integration work, update this branch against main, resolve any conflicts, run the relevant document checks, merge and push main, then update `NOW.md`. Afterward start [B3b.1](../stages/shared-parts.md) under a fresh Pencil claim: inspect the active `classic.pen`, complete shared parts in both themes, show Jafar the designs, and build the approved parts. Use [B3b inventory](b3b-inventory.md) as the starting list.
