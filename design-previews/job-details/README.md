# Uplift job details — design exploration 01

Static HTML and SCSS concept requested by Jafar, with an independent visual system. Sample data and illustrative controls; no app connection. Open index.html directly. CSS and Tabler SVG icons are included, with no network dependencies.

## Direction

Forest navigation, warm neutral canvas, restrained sage status colors, compact summary, and clear white work panels. This is a proposed visual adaptation, not an approved replacement for the app design system.

Research: [Linear's interface refresh](https://linear.app/now/behind-the-latest-design-refresh) supports calmer navigation and consistent hierarchy; [Jobber Job Basics](https://help.getjobber.com/en/articles/job-basics/) and [Visits](https://help.getjobber.com/en/articles/visits/) inform the separation of jobs, line items, and scheduled visits. These sources establish reference behavior; the visual composition and colors are our proposal.

Readability refinement: 15px main text, 13px supporting details, 17–18px section headings, stronger secondary contrast, and controls at least 44px tall. The mobile line-item table scrolls horizontally to preserve readable text. Decorative map lettering is smaller.

Screen checks: rendered at 1440px and 390px with Playwright. Fixed narrow client cards on phones. No document overflow at either width. Static overview only; loading, errors, editing, and dark mode are outside this concept.

Compile styles from the repo root: `npx sass design-previews/job-details/style.scss design-previews/job-details/style.css --no-source-map`.
