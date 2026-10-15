# Classic theme redesign — now

**Goal:** Redesign and rebuild the whole application in stages with fresh, useful Classic concepts: premium,
polished, modern, colorful, clear and calm. Research the user's task; keep an existing idea only when it works
best. Jafar approved multicolor icons and the
design → approval → build → live check → synchronize shared parts → clean loop on 2026-10-15.

**Plan:** `docs/classic-theme-redesign-behavior-contract.md` · **Order:** `ROADMAP.md`.
**Stage:** First delivery. B1–B3 are integrated. B4 Save bar is built, live-checked and awaiting integration
from `codex/b4-save-bar-integration`; [proof](parts/b4-save-bar.md). This replan branch
`codex/classic-redesign-approved-plan` starts from that candidate and waits for B4 integration before merging.

**Next:** Integrate B4, then this approved replan. Start [B3b.1](stages/shared-parts.md): complete the
reusable Pencil parts needed by approved screens, show Jafar changed visuals, then build
them before B5. Finish each screen before advancing. [Record build](stages/first-version-build.md)
and [whole-app stages](stages/whole-app.md) have the done-checks.

**Approved designs:** six record pages; five lists ([Clients](parts/clients-list.md),
[Requests/Quotes/Invoices](parts/requests-quotes-invoices-lists.md), Jobs in the list-design branch);
Schedule views, drawer and quick-create ([note](parts/schedule-design.md)). Home/Reports is coordinated with
`crm-launch-readiness` [Part 13](../crm-launch-readiness/parts/part-13-home-reports.md); its remaining design
choice does not block the first delivery.

**Limits:** Settings' old layout still clips on phone; its later stage fixes it. Botanical stays unchanged.
