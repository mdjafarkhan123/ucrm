# Part 13 — Home screen and Reports

**Campaign:** crm-launch-readiness · **Plan:** `docs/home-and-reports-behavior-contract.md`
**Stage:** Design
**Code:** `main` (plan merged 2026-10-12; build work starts a new `codex/` worktree)
**Done when:** Figures match the books and respect each person's permissions
**Read next:** `.claude/skills/design/SKILL.md` § "Design in Pencil first"; the plan's Home and Reports sections

## Steps

- [x] Research Jobber Home, Insights and Reports, and our data — `docs/research/home-and-reports-2026-10-12.md`
- [x] Plan written, fresh-reviewed, approved by Jafar 2026-10-12; reconciliation contract amended the same day
- [x] Design in `classic.pen` below the Classic design system: Home (owner, field worker), Reports › Insights,
      All reports list, one report screen (Invoices) and Money owed — desktop 1440px only (Jafar 2026-10-12: no
      phone designs needed). New parts in design-system section "06 App shell & data".
- [ ] Jafar's yes on the designs, recorded here with screen names and date
- [ ] Split the build into parts (To Tickets) and record them in the roadmap
- [ ] Build, verify, screen check, live proof

## Next

Show Jafar the six screens in `classic.pen` (row below the design-system page): "Home · Owner · 1440",
"Home · Field worker · 1440", "Reports · Insights · 1440", "Reports · All reports · 1440", "Reports · Invoices
report · 1440", "Reports · Money owed · 1440", "Home & Reports · States · 1440"; and section "06 App shell & data" (new parts: Sidebar, Top bar, Nav
item, Trend, Metric, Date range + menu, Bar chart, Ranked bars, Donut meter, Chart empty, Aging bar, Report tile,
Report link, Workflow column, Visit row). On his yes: record it above, commit `classic.pen` from the main folder,
then To Tickets. Building these parts in code needs a chart approach (no chart library in `package.json`; the
designs use plain bars, a donut and stacked bars, so SVG/CSS without a library may be enough — decide at build).

## Notes

- Build must include: list pages read `?status=` from the address; `reports.view` permission outside
  `reporting.advanced` (`src/lib/server/access/effective.ts`); tips recorded on payment events with backfill;
  cash-basis tax reader and export file; Money owed rule applied to `invoice_money_overview` and the aging reader;
  derived invoice paid date; Visit value rule. No chart library exists yet (`package.json`).
- Design choices to confirm with Jafar: Home shows both the top bar "Add New" and the plan's header "New" menu
  (duplicate); headline figures of $1,000+ on Home and Insights drop cents, report tiles and tables keep them. Use
  tabular figures for every number column in code.
- `/api/requests/counts` checks only membership, not `requests.view` — fix when Home uses it.
