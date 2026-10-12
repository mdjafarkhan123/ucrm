# Part 13 — Home screen and Reports

**Campaign:** crm-launch-readiness · **Plan:** `docs/home-and-reports-behavior-contract.md`
**Stage:** Design
**Code:** `main` (plan merged 2026-10-12; build work starts a new `codex/` worktree)
**Done when:** Figures match the books and respect each person's permissions
**Read next:** `.claude/skills/design/SKILL.md` § "Design in Pencil first"; the plan's Home and Reports sections

## Steps

- [x] Research Jobber Home, Insights and Reports, and our data — `docs/research/home-and-reports-2026-10-12.md`
- [x] Plan written, fresh-reviewed, approved by Jafar 2026-10-12; reconciliation contract amended the same day
- [ ] Design in `classic.pen` below the Classic design system: Home (owner, field worker), Reports › Insights,
      All reports list, one report screen (Invoices) and Money owed — each at 1440px and 390px
- [ ] Jafar's yes on the designs, recorded here with screen names and date
- [ ] Split the build into parts (To Tickets) and record them in the roadmap
- [ ] Build, verify, screen check, live proof

## Next

Design session (Jafar said 2026-10-12: no design in the research session). In Pencil, check `get_app_state` shows
`classic.pen`. The file has no app shell (sidebar and top bar) yet: screenshot the real app shell first
(`src/lib/components/layout/SharedAppShell.svelte`, logins in `Login.md`) and add it to the design-system page as a
reusable part, then build screens from existing parts (KPI card `h0NPZr`, Data table `Jz0kh`, Card `GF3sS`, Page
header `s8m85y`, Tabs `CwczH`, Segmented control `qMkSl`, Status badge `qWJES`). Charts use the `color-dataviz-*`
variables. A date-range picker and a chart are new kinds of part: add them to the design-system page first.

## Notes

- Build must include: list pages read `?status=` from the address; `reports.view` permission outside
  `reporting.advanced` (`src/lib/server/access/effective.ts`); tips recorded on payment events with backfill;
  cash-basis tax reader and export file; Money owed rule applied to `invoice_money_overview` and the aging reader;
  derived invoice paid date; Visit value rule. No chart library exists yet (`package.json`).
- `/api/requests/counts` checks only membership, not `requests.view` — fix when Home uses it.
