# New Quote — implementation

**Stage:** Verified in preview, waiting to merge. Approved A: Batch 34 `B5DLv` / `q7Cn1w`; shared money-card
look: Batch 35. Parent agreement: `docs/contractor-design-concept-behavior-contract.md`.

**Scope:** Reuse the existing shared header, layout, pricing, notes, files, rail rows and save bar. Preserve
all fields, permissions, API writes, retry behaviour and calculations. Optional blocks become the approved
slim cards. Extend the existing money-card renderer; no second summary implementation.

**Saved work:** `codex/new-quote-concept-build`, worktree
`/home/jafar/.codex/worktrees/new-quote-concept-build/Ucrm`, reservation `19b9c22c0477`.

**Proof:** `docs/evidence/2026-10-21-new-quote-page/README.md`. Focused type check, lint and Svelte review passed.
Screen checks cover 1440 light/dark, priced data, optional sections, long title/error, 390 light/dark. Quote
#47 (`ccdc5ea2-d95e-454c-8a8a-5ec5a3075962`) proves Save: $125 service, 10% discount, 10% tax = $123.75, draft.
Do not create a duplicate proof record.

**Limits:** Unsaved forms have only a running subtotal. Profit/final totals remain server-calculated after
Save; the card explains this. The complete Batch 35 job-stage/invoice-context content and pre-save profit
preview remain unfinished. New Invoice and Request still need their approved page/header rollout.

**Next:** Main is reserved by `3237d361e057` (Customer group Pencil session). Asked Jafar if that session is
closed; no answer yet. Do not release it by age. Once released or Jafar confirms it closed, update against
main, claim integration, merge and push, then recheck the public `/quotes/new`, update the Built tick and tidy
Pencil (no canvas edits were made in this build). The current worktree preview runs on port 5174; process ID
is in `/tmp/ucrm-new-quote-preview.pid`.
