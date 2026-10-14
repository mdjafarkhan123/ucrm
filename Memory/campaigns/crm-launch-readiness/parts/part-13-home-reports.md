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
  - [x] `Home · Owner · 1440` (`m4ICXz`, y 17700) — fresh concept 2026-10-14 after Jafar deleted the first
        draft; light and dark checked; awaiting his review. New parts drawn inline (Today card, To do columns
        with values, Business performance compare bars) — promote to § 09 after his yes
  - [ ] The other five screens and states, **one screen per session** (Jafar 2026-10-14); § 09 dark page
- [ ] Jafar's yes on the designs, recorded here with screen names and date
- [ ] Split the build into parts (To Tickets) and record them in the roadmap
- [ ] Build, verify, screen check, live proof

## Next

Jafar, 2026-10-14: this is a **redesign, not a conversion** — new layouts in the record pages' language
(header card with key-fact tiles, lifecycle-style track, main column + 336 rail, one dark featured card),
Dribbble quality. Keep the plan's content and permissions; change layout freely.

1. Ask Jafar for feedback on `Home · Owner · 1440` (`m4ICXz`) and the question below; apply it.
2. Next session draws ONE more screen (Jafar 2026-10-14), researched first. Jafar deleted the
   `Working copy · …` frames; the `Old look · …` frames (y 15740) hold the content. Ideas: Insights — Revenue chart in the dark
   featured card, overview figures as key-fact tiles; All reports — Settings-home groups (Group header
   `ILY7B` + Setting row `lWM0h`); report screens — sub-page header with back link, date range, Download CSV,
   tile filters, table card with totals row; Money owed — aging bar as hero.
3. After his yes: delete the `Old look · …` frames, add § 09 to the dark design-system page, record the yes.

Pending question for Jafar: "The approved plan put a 'New' button in the Home header. The new top bar
already has 'Add new' on every page, which does the same thing. I left the extra button out so there aren't
two identical buttons on one screen. Is that OK?"

## Notes

- Build must include: list pages read `?status=` from the address; `reports.view` permission outside
  `reporting.advanced` (`src/lib/server/access/effective.ts`); tips recorded on payment events with backfill;
  cash-basis tax reader and export file; Money owed rule applied to `invoice_money_overview` and the aging reader;
  derived invoice paid date; Visit value rule. No chart library exists yet (`package.json`).
- `/api/requests/counts` checks only membership, not `requests.view` — fix when Home uses it.
