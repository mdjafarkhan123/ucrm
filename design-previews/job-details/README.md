# Job details — design concept 01

A standalone, disposable HTML/SCSS proposal for a new Uplift visual system. The live application is unchanged. All records are fictional; buttons show a preview notice. Section links scroll through the overview rather than implementing real tabs.

Run from this checkout:

```sh
python3 -m http.server 4188 --bind 127.0.0.1 --directory design-previews/job-details
```

Open http://localhost:4188. HTML includes local inline Tabler icons, with no external fonts or assets. Edit `styles.scss`, then compile with `npx sass design-previews/job-details/styles.scss design-previews/job-details/styles.css --no-source-map`.

## Research and proposal

- [Jobber Job Basics](https://help.getjobber.com/en/articles/job-basics/): preserve the distinction between the overall job, visits, and line items. Put the next visit above the work scope.
- [Linear's interface refresh](https://linear.app/now/behind-the-latest-design-refresh): consistent header actions and quieter navigation inform the shell hierarchy. Forest colors, warm surfaces, typography, and card treatment are our own proposal, not verified competitor behavior.
- Existing app component inventory includes WorkRecordHeader, JobVisitsSection, JobBillingCard, and Sidebar. This plain HTML proposal does not import Svelte components; production implementation should reuse those behavior boundaries.

New design tokens: forest navigation #172e26; primary #23674b; canvas #f6f7f4; ink #202e29; borders #e6e9e5; 7–10px component radii; system sans typography; restrained shadows; one primary job action. Jobber behavior stays the reference. No production design or workflow decision has been approved by this prototype.

## Verification

Compiled with Sass and checked with Prettier. Chromium rendered 1440px desktop and 390px mobile with no page overflow. Preview action notice checked. Screenshots visually reviewed. The line-item table scrolls horizontally on mobile. This is a visual concept, not a production accessibility or behavior audit.

## Expanded section coverage

Compared with the current job page on 2026-10-10: added full visits, labor/time, expenses, checklists, crew instructions, photos/files, sign-off, work report, costing, billing reminders, discount/tax controls, and originating quote. The existing summary, scope, customer, billing overview, notes, and activity remain. Recurring-period and per-visit billing queues do not apply to this fixed-price one-off example. Sample cost totals are internally consistent: $8,450 revenue − $960 labor − $2,900 expenses = $4,590 profit before tax, with 54.3% margin. All controls remain static preview affordances.

## Combined design — small review pieces

Jafar requested combining this concept with the strongest parts of `codex/job-design-concept`, working piece by piece. This branch is the proposed combined preview; it does not supersede campaign approval records yet.

1. Customer/property card: adapted the companion concept's illustrated map, kept this concept's customer contacts and message action, and made directions a full-width link. The illustration is labelled and does not claim a geocoded location. Ready for visual review.
2. Next: sidebar/header comparison and readability. Review that piece before changing the work sections.
3. Then: visits/scope; time/expenses/checklists; notes/files/sign-off/report; financial supporting column. Each is a separate reviewable change.
4. Finally: bring across the companion demo's applicable modal previews and scenario coverage in small groups, preserving existing functionality and checking desktop/mobile after each group. Keep the companion branch as the interaction reference.

Keep the wide work column and narrow supporting column throughout. Each piece has a focused change, browser evidence, and a commit. The full milestone remains unapproved until layout, coverage, interactions, and scenarios are reviewed together.
