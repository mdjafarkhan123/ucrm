# Classic theme redesign — stage: first-version build

**Plan:** `docs/classic-theme-redesign-behavior-contract.md` · **Look:** `docs/classic-theme-redesign-design-recipe.md`
and the approved `classic.pen` frames. Order and size approved by Jafar 2026-10-13 ("all agreed").

Every page part adapts its phone layout (390px screen check), works in light and dark, keeps every action, role
and save rule, and proves its main journey once on the live app. Botanical must look unchanged after each part.
Between parts, local pages may mix old and new looks; no customer sees it.

| Part | Plan section | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- | --- |
| B1 Classic's own colours | § Assumptions; recipe § Tokens | The `classic2` tokens (light and dark) in code, reaching only Classic pages and their pop-ups, through the CRM design system's theme foundation; Classic design skill takes the new values | — | Token values match the recipe; Classic page, dialog and menu read them; the Botanical preview (`DESIGN_SHELL_PREVIEW=botanical`) screenshots unchanged | Done 2026-10-13 — [proof](../../../../docs/research/classic-theme-b1-2026-10-13.md) |
| B2 Sidebar and top bar | § The app shell…; § "Soon" menu items; recipe § Page and shell | Black-green sidebar (brand block, collapsed state), Soon items hidden, top bar search, "Add new", avatar, page background — every page, Control Room included | B1 | Matches `Settings · Home · 1440` shell; collapse, mobile drawer, search and notifications still work | Done 2026-10-14 — [proof](../parts/b2-shell.md) |
| B3 Cards, buttons, fields, pills | § Card shells change everywhere; recipe § Cards and rows, § Fields and buttons | `SectionBlock`, `RailCard`, buttons, fields, status pills, segmented control in the new look on every Classic page | B1 | Settings and a sample of other pages show only the new card style; focus, disabled and error states match the design-system page | In progress — styling implemented and build passes; live screen check pending because no browser surface was available 2026-10-14; [checkpoint](../parts/b3-shared-ui.md) |
| B4 Save bar | § Settings additions (Save bar wording); recipe § Save bar | New Save bar with "You have unsaved changes"; resting state on full-page forms | B3 | Bar appears exactly when it did before; resting state shows on full-page forms; Save and Cancel behave as before | Not started |
| B5 Work-record header card | § Approved additions; recipe § Record page structure | Record frame and header card on request, quote, job, invoice and payment: lifecycle track, key facts, Call / Message / Directions | B3 | Track lights the right step and links real records; Message opens the same dialog as the client page; buttons show only to roles allowed today | Not started |
| B6 Job details | § Job details approved; § Approved additions | Green profit card, visits with live on-site time, Work log tabs, close-out list, rail cards, notes and photos | B5 | Matches `Job details · 1440`; success check "without scrolling" passes; every job action works | Not started |
| B7 Line items and totals | § No duplicated UI; § Quote details approved | Line items on pages and create/edit forms; totals; one "Discount and tax" card | B3 | Create, edit and save of each record's lines unchanged; totals match before and after | Not started |
| B8 Quote details | § Quote details approved | Approved quote page; sent quote shows no edit pencils | B5, B7 | Matches `Quote details · 1440`; every quote action works | Not started |
| B9 Invoice details | § Invoice details approved | Approved invoice page: Terms & dates row, History tabs, balance-due card | B5, B7 | Matches `Invoice details · 1440`; every invoice action works | Not started |
| B10 Request and Payment details | § Request, Payment and Client details approved | Both approved pages, payment receipt preview and "Applied to" first | B5, B7 | Match their 1440 frames; receipt view and print work | Not started |
| B11 Client details | § Request, Payment and Client details approved | Approved client page: green summary card, Source and marketing card, Upcoming / Past, tabs at the header's foot | B6 | Matches `Client details · 1440`; every client action works | Not started |
| B12 Final check | § Success checks | All six pages in dark and at 390px, every role's actions, Botanical unchanged, proportional performance check, Jafar's browser walk-through | B1–B11 | Every success check passes with evidence; Jafar says yes after his walk-through | Not started |
