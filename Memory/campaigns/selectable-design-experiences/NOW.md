# Selectable design experiences — now

**Goal:** Preserve Classic and offer Botanical with different layouts over shared behaviour, downloading only the selected presentation and shared foundations.
**Plan:** `docs/selectable-design-experiences-behavior-contract.md`

**Progress:** Parts 1–2 are done. Part 3 has a release baseline, gated synthetic fixture, browser verifier and saved evidence. Plain universal-load dynamic imports failed selected-only delivery: SvelteKit links both designs' CSS. Classic application files remain unchanged.

**Next part:** Resume Part 3 from `parts/3-selected-loading-proof.md`. Investigate selected SSR stylesheet delivery and separate server/browser import graphs; keep the verifier failing until the mechanism actually passes. Evidence and repeat commands: `docs/research/selectable-design-loading-2026-10-11.md`. Real shell migration has not started. No production deployment is authorized.

**Blockers:** Botanical dark appearance and full coverage require focused approval before public selection; they do not block the private loading proof.
