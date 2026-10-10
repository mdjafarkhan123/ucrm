# Selected Uplift design reference — v3

Open `/demo/job-details` on the running application. It redirects to `/demo/job-details/index.html`.

This is the canonical browser reference selected by Jafar on 2026-10-10: Botanical v3 with balanced type sizing and five sample visits. Earlier concept variants remain archived in the design preview branch. Work on this reference in small reviewed pieces; preserve the consistent main/supporting columns and readable type. The companion `codex/job-design-concept` demo remains the reference for deeper modal/scenario coverage still to migrate.

The preview is intentionally standalone HTML/SCSS, served using SvelteKit's static assets convention. No login is needed because every record is fictional. It is marked noindex. It has no API writes, sends, real uploads or persistent changes. Title/instructions edits reset on reload; other commands are labelled previews. Map and photo imagery are labelled illustrations. This route does not apply the design to production job pages or approve the entire campaign milestone.

Edit `styles.scss` and compile from the repository root:

```sh
npx sass static/demo/job-details/styles.scss static/demo/job-details/styles.css --no-source-map
npx prettier --write static/demo/job-details/styles.scss static/demo/job-details/styles.css
```

Typography: main text roughly 15px, supporting details 13px, section headings 18px, with medium/semibold emphasis and darker supporting text. Decorative labels can be smaller. Desktop refinement is approved for comparison; phone and outdoor readability need later verification.

Research: [Material color roles](https://m3.material.io/styles/color/the-color-system), [Atlassian accents](https://atlassian.design/foundations/color/accents), [Linear hierarchy](https://linear.app/now/behind-the-latest-design-refresh), [Jobber job structure](https://help.getjobber.com/en/articles/job-basics/). The exact visual treatment is our adaptation, not a user-tested result.
