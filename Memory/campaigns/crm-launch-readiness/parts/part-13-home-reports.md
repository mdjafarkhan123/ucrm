# Part 13 — Home screen and Reports

**Campaign:** crm-launch-readiness · **Plan:** `docs/home-and-reports-behavior-contract.md`
**Stage:** Design
**Code:** `main` (plan merged 2026-10-12; build work starts a new `codex/` worktree)
**Done when:** Figures match the books and respect each person's permissions
**Read next:** `.claude/skills/design/SKILL.md` § "Design in Pencil first"; recipe `docs/classic-theme-redesign-design-recipe.md`

## Steps

- [x] Research Jobber Home, Insights and Reports, and our data — `docs/research/home-and-reports-2026-10-12.md`
- [x] Plan written, fresh-reviewed, approved by Jafar 2026-10-12; reconciliation contract amended the same day
- [ ] Redesign in `classic.pen` in the new Classic look, desktop 1440 only (classic-theme-redesign rule):
      Home (owner, field worker), Reports › Insights, All reports, Invoices report, Money owed, states
  - [x] Design-system page (light) § "09 Numbers & charts": Trend, Metric, Date range, Donut meter, Chart
        empty, Avatar, Bar chart, Ranked bars, Aging bar, Report tile, Report link, Workflow column, Visit row,
        Tabs, Banner; Segmented control `LQ6rJ` gained two hidden options
  - [x] **`Home · Owner · 1440` (`G8yMte`, x 0 y 17593) approved by Jafar 2026-10-14** ("ok I approved
        your version"). It began as the Opus review concept: one reviewer's Variant B with every fact shown
        once — compact dark Today header (green = on site now, pale = done; "1 late" / "1 unassigned" chips),
        68px Visit rows, Money owed age table (grey not due → amber → red), "Ending soon" as a third To do ›
        Jobs line. The approved screen settles the review's open choices: no crew map, no double-booking
        warning on Home, no "needs a look" strip or reminder banner, no header "New" button (the top bar's
        "Add new" covers it). Jafar deleted every other Home owner version, including the 2:30 PM entry's
        `m4ICXz` (he answered "I delete all except your one" when asked which approval stands)
  - [ ] The other five screens and states, **one screen per session** (Jafar 2026-10-14); § 09 dark page
- [ ] Jafar's yes on the designs, recorded here with screen names and date
- [ ] Split the build into parts (To Tickets) and record them in the roadmap
- [ ] Build, verify, screen check, live proof

## Next

Jafar, 2026-10-14: this is a **redesign, not a conversion** — new layouts in the record pages' language
(header card with key-fact tiles, lifecycle-style track, main column + 336 rail, one dark featured card),
Dribbble quality. Keep the plan's content and permissions; change layout freely.

1. Next session draws ONE more screen (Jafar 2026-10-14), researched first. Jafar deleted the
   `Working copy · …` frames; the `Old look · …` frames (y 15740) hold the content. Ideas: Insights — Revenue chart in the dark
   featured card, overview figures as key-fact tiles; All reports — Settings-home groups (Group header
   `ILY7B` + Setting row `lWM0h`); report screens — sub-page header with back link, date range, Download CSV,
   tile filters, table card with totals row; Money owed — aging bar as hero.
2. After his yes on all six: delete the `Old look · …` frames, add § 09 to the dark design-system page, record the yes.

Resolved 2026-10-14: the approved Home has no header "New" button; the top bar's "Add new" does that job.

## Notes

- Build must include: list pages read `?status=` from the address; `reports.view` permission outside
  `reporting.advanced` (`src/lib/server/access/effective.ts`); tips recorded on payment events with backfill;
  cash-basis tax reader and export file; Money owed rule applied to `invoice_money_overview` and the aging reader;
  derived invoice paid date; Visit value rule. No chart library exists yet (`package.json`).
- `/api/requests/counts` checks only membership, not `requests.view` — fix when Home uses it.
