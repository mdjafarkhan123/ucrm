# Batch 33 — shared number cards

**Stage:** Done — merged into main and confirmed on the live app 2026-10-21.
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

**Integration:** Jafar explicitly authorised merging while preserving Claude Code's unsaved design files
on 2026-10-21. Integration branch `codex/kpi-integration`, claim `b4549b3c7e32`, combines the current main
and the built branch. The new approved Money summary card guidance from Claude is retained.

**Live proof:** `https://app.upliftcontractor.com/jobs` shows all six shared number cards with real owner
data; screenshot `docs/evidence/2026-10-21-kpi-cards/main-jobs-live.jpg`. Guide and Pencil file hashes were
unchanged through the merge. No further long checks ran.

**Next:** the remaining approved shared batches (24, 26–30), New Quote, or the newly approved Batch 35 money
summary card. This KPI delivery is complete; claims can release and temporary worktrees can archive.
