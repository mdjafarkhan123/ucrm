# A1 — reuse and prove the delivery seam

**Campaign:** crm-design-system · **Plan:** `docs/crm-theme-foundation-behavior-contract.md` § Foundation completion checks
**Stage:** Build planning and proof; not complete.
**Code:** Resume from current `main` in a reserved temporary worktree.
**Done when:** The A1 done-check in `../stages/theme-foundation.md` passes.
**Read next:** `docs/research/crm-theme-foundation-delivery-design-2026-10-12.md`; existing shell and selected-loading evidence.

## Saved position

Planning Parts 1 and 2 were approved on 2026-10-12. Botanical approval covers sequence/coverage only, not new visuals. Foundation delivery remains outstanding. No fresh runtime or database proof was run in this handover.

An earlier source-only check found the following; recheck against latest main before relying on it:

- `(app)/+layout.ts` selects one presentation frame. Existing local preview and synthetic loading fixtures cannot establish saved organization choice or complete page/style isolation.
- `src/lib/design-loading-proof/loaders.ts`, `/demo/design-loading/[design]/[surface]`, `scripts/verify-real-design-shell.mjs` and `scripts/verify-selected-design-loading.mjs` provide reusable starting points. Verify fixture gates before running; fixtures must not alter public preferences.
- `RecordDetailLayout.svelte` exposes editing/dirty/saving state, but no common apply-safety registry was established. `RecordFormLayout.svelte` also needs inventory; bespoke settings guards do not prove whole-workspace safety.
- Inventory child save owners, composers, uploads and hidden dialogs. Retained view state includes in-memory job filters and pipeline URL filters, selected cards and scroll position; route preservation alone is insufficient.
- Page/control styling still uses a shared graph. Selected-shell evidence does not prove inactive page, dialog or font assets stay unloaded.

## Next

Reserve A1, load the applicable source/design/performance guidance, and compare actual source with the existing evidence. Reuse unchanged proof where valid. Complete the presentation/style seam and edit/apply/view-state inventory; split later safety work into bounded batches before implementation. Run the appropriate private fixture and screen checks for changed surfaces. Record actual evidence and limits before calling A1 complete.

## Existing evidence and limits

`docs/research/selectable-real-shell-2026-10-11.md` covers selected shell behavior with owner/field and desktop/phone examples. It does not prove complete themes, dark readiness, safe drafts or persistence. Its reported dashboard performance findings remain unresolved; do not describe theme overhead or whole-app speed as verified.
