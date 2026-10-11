# Selectable design experiences — now

**Goal:** Preserve Classic and offer Botanical with different layouts over shared behaviour, downloading only the selected presentation and shared foundations.
**Plan:** `docs/selectable-design-experiences-behavior-contract.md`

**Progress:** Parts 1–3 are done. Svelte's component CSS injection passes the private release-build SSR, hydration, asset and warming proof at desktop/phone widths. Cold authenticated Classic baseline is saved; real shell and global styles remain unchanged.

**Next part:** Part 4, approved shared shell. Read the roadmap line, `docs/adr/0009-selected-presentation-component-css.md` and `docs/research/selectable-design-injected-css-2026-10-11.md`, then the approved shell record. Extend the proven seam to real dependencies, preserve Classic and shared behaviour, and rerun the saved authenticated baseline. Its existing cold dashboard loading and phone movement need investigation. Full type checking remains unverified because the command stalls. No production deployment is authorized.

**Blockers:** Botanical dark appearance and full coverage require focused approval before public selection; they do not block the private loading proof.
