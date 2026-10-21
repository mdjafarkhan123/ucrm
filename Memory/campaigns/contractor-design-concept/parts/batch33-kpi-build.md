# Batch 33 — shared number cards

**Stage:** Built and browser-verified; waiting to merge into the live app.
**Approval:** B, `concept.pen` board `fzPaM`, Jafar 2026-10-21.
**Branch:** `codex/concept-kpi-cards`.
**Workspace:** `/home/jafar/.codex/worktrees/concept-kpi-cards/Ucrm`; claim `8aca80f71684`.

KpiCard is the one shared card: 48px tile, number and label beside it, corner arrow, note band, filter ring,
critical state, green summary. AttentionCard lays those cards on the page with the existing facts and tags.
Connected Clients (4), Quotes/Invoices (5), Requests/Jobs (6); Reviews uses its existing shared cards.
Existing report/settings/admin callers keep compatible props and receive the new appearance.

Queries, values, price permissions, filter toggling and resolved links stay unchanged. Supporting figures
stay in the green note band. Long amounts stack below the tile and shrink readably on narrow cards.
Dark mode uses existing tokens; no separate dark board was drawn. Pencil and its unsaved designer work
were untouched. The design modules now describe the approved number-card appearance.

**Proof:** `docs/evidence/2026-10-21-kpi-cards/README.md`: six real pages at 1440/390 light/dark; Jobs 3+3 at
900; filter/keyboard proof and temporary fixture states. Compiler/MCP clean for shared cards; focused types
0 errors/warnings; 22 existing tests passed. Further long checks deferred per Jafar's instruction.

**Next:** merge and push when main is available. Main is still reserved by Claude's design session
(`2acb18fc222c`) and has unsaved Pencil/guide changes. Preserve those changes; coordinate the integration
under `docs/agent-concurrency.md`. Update the approved-batch row and NOW once combined; release afterward.
