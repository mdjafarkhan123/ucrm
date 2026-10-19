# Part 11 — Trim and clarify

**Campaign:** memory-skill-upgrade · **Plan:** `docs/memory-campaign-workflow-behavior-contract.md`
**Stage:** Verifying
**Code:** worktree `.worktrees/campaign-memory-trim`, branch `claude/campaign-memory-trim` — Waiting to merge
**Done when:** final-version trials pass and the branch is merged to `main` with Jafar's approval
**Read next:** `docs/research/campaign-memory-trim-proof-2026-10-19.md`

## Steps

- [x] Review: usage, sizes, clarity; Jafar approved the restructure (2026-10-19)
- [x] Trials of the old skill (all six)
- [x] Shorter skill with resume, start, and save rules; `finishing.md`; Memory checker
- [x] Jafar (2026-10-19): Campaign Memory is handover memory only; CLAUDE.md routes planning skills;
      `to-spec`, `to-tickets`, `wayfinder` manual only again; `planning.md` removed
- [x] Middle-version trials (three of six, plus a read-only real-campaign trial); their fixes applied
- [ ] Final-version trials, at least S3 and S7 — only with Jafar's yes
- [ ] Merge to `main` with Jafar's yes, then push, release the claim, and remove the worktree
- [ ] Finish the part: Part 11 and Part 3 Done in the roadmap, `NOW.md`, index row

## Next

Ask Jafar the two questions below. If he says yes to trials, build the copies with
`docs/research/campaign-memory-trials/make_fixture.py` in the scratch folder, run S3 and S7 with its prompt,
and add the results to the proof file.

Questions for Jafar, word for word:

1. "Should I run the two final tests (starting a new campaign, and resuming a half-done plan)? They take about
   10–15 minutes and roughly 250,000 tokens. Or should I skip them, and you try the new skill yourself?"
2. "Can I put the new skill into your main project now?"

## Notes

- Handover: Jafar paused this session on 2026-10-19. Claim `7f1be2fcd158` (claude-skill-trim-opus) stays held
  for the unmerged branch; this note is the explicit handover, so the next session may release it and claim
  again from the worktree.
- Ask Jafar before launching trial agents; he stopped unrequested runs on 2026-10-19.
- Main's folder holds Jafar's unsaved wording edit to `.claude/skills/campaign-memory/SKILL.md`. The branch
  carries it (commit `1ece402d`), so before merging, ask Jafar to let that uncommitted copy be reset.
- For Part 4: the checker lists 29 notes over their word limit and two campaign folders without index rows.
