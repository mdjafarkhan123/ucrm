# Classic theme redesign — stage: first-version build

**Plan:** `docs/classic-theme-redesign-behavior-contract.md` · **Look:** `docs/classic-theme-redesign-design-recipe.md`
and the approved `classic.pen` frames. B1–B12 were approved 2026-10-13; the shared-parts-first and
screen-by-screen order below was approved 2026-10-15.

Complete [B3b shared parts](shared-parts.md) after B4 and before B5. B5 and B7 prepare shared record pieces;
then finish each page in turn. A page is done only after its approved Pencil design matches the real screen,
its main journey works for the permitted roles at desktop and 390px in light/dark, shared design changes are
synced, and its superseded styling and rejected variants are removed. Botanical must stay unchanged.

| Part | Plan section | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- | --- |
| B1 Classic's own colours | § Technical boundaries; `classic.pen` design system | The `classic2` tokens (light and dark) in code, reaching only Classic pages and their pop-ups, through the CRM design system's theme foundation; Classic design skill takes the new values | — | Token values match Pencil; Classic page, dialog and menu read them; the Botanical preview (`DESIGN_SHELL_PREVIEW=botanical`) screenshots unchanged | Done 2026-10-13 — [proof](../../../../docs/research/classic-theme-b1-2026-10-13.md) |
| B2 Sidebar and top bar | § Design target; `classic.pen` Settings reference | Black-green sidebar (brand block, collapsed state), Soon items hidden, top bar search, "Add new", avatar, page background — every page, Control Room included | B1 | Matches `Settings · Home · 1440` shell; collapse, mobile drawer, search and notifications still work | Done 2026-10-14 — [proof](../parts/b2-shell.md) |
| B3 Cards, buttons, fields, pills | § Shared building blocks; `classic.pen` design system | `SectionBlock`, `RailCard`, buttons, fields, status pills, segmented control in the new look on every Classic page | B1 | Settings and a sample of other pages show only the new card style; focus, disabled and error states match the design-system page | Done 2026-10-14; [proof](../parts/b3-shared-ui.md) |
| B4 Save bar | § Approved additions; `classic.pen` design system | New Save bar with "You have unsaved changes"; resting state on full-page forms | B3 | Bar appears exactly when it did before; resting state shows on full-page forms; Save and Cancel behave as before | Ready to merge — live Classic, Save/Cancel, phone and Botanical checks complete; candidate based on `32e5b80d`; waiting for the active main writer to save and release; see [proof](../parts/b4-save-bar.md) |
| B5 Work-record header | § Shared building blocks; recipe § Record page structure | Reusable record frame, lifecycle track, key facts, Call / Message / Directions | B3b | Track and links use real records; Message and role rules match today | Not started |
| B7 Line items and totals | § Shared building blocks | Reusable line items and totals for details and create/edit forms | B3b | Create, edit and save still work; totals agree before and after | Not started |
| B6 Job details | § Design principles | Approved Job concept: profit, visits, Work log, close-out, notes and photos | B5, B7 | Owner sees stage, today's visit, total and next invoice step without scrolling; all job actions pass the page loop | Not started |
| B8 Quote details | § Design principles | Approved Quote concept and sent-state rules | B6 | All quote actions pass the page loop; a sent quote has no edit pencils | Not started |
| B9 Invoice details | § Design principles | Approved Invoice concept: dates, history and balance | B8 | All invoice actions and totals pass the page loop | Not started |
| B10a Request details | § Design principles | Approved Request concept | B9 | Assessment and conversion actions pass the page loop | Not started |
| B10b Payment details | § Design principles | Approved Payment concept, receipt preview and Applied to | B10a | Receipt view, print and payment actions pass the page loop | Not started |
| B11 Client details | § Design principles | Approved Client concept: summary, source, visits and tabs | B10b | All client actions pass the page loop | Not started |
| B12 First-delivery check | § Success checks | Six completed record pages and their shared parts | B11 | Cross-page role, phone, dark, Botanical and proportional performance checks pass; Jafar's browser tour is complete | Not started |
