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
