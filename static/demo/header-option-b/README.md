# Header option B — proposal

Jafar requested another visible header before choosing. Only the existing variant 2 revision 2 sidebar
is approved. Compare `/demo/header-option-b/index.html` with `/demo/app-shell-v2/index.html`.

This alternative uses a two-line page identity, framed search and a green Add New action. Phone search
gets its own row instead of shrinking to an icon. This trades a little vertical space for a visible
search label. These are proposed visual adaptations of Botanical foundations; no new behavior is
introduced. Existing research and capability inspection remain in `../app-shell/README.md`.

Sidebar CSS and demo JavaScript are shared with variant 2. All actions remain fictional and reset on
reload. Search internals, dialog styling, dark palette and application rollout await separate review.
Compile with `npx sass static/demo/header-option-b/styles.scss static/demo/header-option-b/styles.css --no-source-map`.

## Research behind this alternative

- [Carbon global header](https://www.carbondesignsystem.com/building-blocks/core/patterns/global-header):
  global utilities have a consistent home. We group appearance, notifications and account controls
  on the right and retain the existing Add New capability without inventing destinations.
- [Linear interface refresh](https://linear.app/now/behind-the-latest-design-refresh): clear hierarchy
  and predictable action positions. We distinguish page identity, search and utilities through spacing.
- [NN/g search](https://www.nngroup.com/articles/state-ecommerce-search/): visible desktop search
  is recommended in its ecommerce context. Applying that discoverability idea to CRM search is our
  adaptation, not direct evidence about this CRM. The phone second row is also our proposed tradeoff.

## Verification

Playwright Chromium checked 1440×900 and 390×900, captured `evidence/1440.png` and `evidence/390.png`,
and confirmed document width equals viewport width. Search for Jobs returns its destination; Escape
closes search. Phone navigation opens and dismisses. Both screenshots were visually inspected for
alignment, spacing and clipping. Full text resizing, assistive technology, all restricted scenarios and
production shell behavior remain for implementation preparation; this is a focused visual proposal.
