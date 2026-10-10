# Job details v2 — desktop review

Separate copy of `../job-details/`; v1 remains unchanged. This is a synthetic HTML/SCSS desktop design proposal, not the real application.

Changes and purpose:

- Larger main, secondary, heading, and control text for comfortable reading.
- One visit section: upcoming work emphasized, completed visits below, without repeating the next visit.
- Crew instructions next to visits, making arrival guidance easier to find.
- Explicit “On this job” jump navigation rather than simulated tab panels.
- Separate team notes and files; illustrated photo thumbnails open a labelled preview.
- Supporting-column billing stages show the paid deposit, invoice reference, and remaining amount consistently with the job total.
- Useful context remains; generic subtitles and the floating preview badge have been reduced.
- Title and instruction editors apply temporary browser changes, support Cancel/Escape, and reset on reload. Other commands remain clearly labelled preview notices. Full scenario and modal migration from the companion demo is still pending.

Research references: [Linear hierarchy and consistency](https://linear.app/now/behind-the-latest-design-refresh), [Jobber job structure](https://help.getjobber.com/en/articles/job-basics/), [W3C contrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html), and [modal dialog guidance](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/). The exact layout and visual treatment are our proposed adaptations.

Desktop verification at 1440px and 1280px: no document overflow or script errors; combined visit counts; title edit/apply/reload reset; photo dialog and Escape. Phone refinement is intentionally deferred at Jafar's request. All data and map/photo illustrations are fictional; no real writes or sends occur.

Run from the checkout: `python3 -m http.server 4189 --bind 127.0.0.1 --directory design-previews`, then open `/job-details-v2/` (or `/job-details/` for v1).
