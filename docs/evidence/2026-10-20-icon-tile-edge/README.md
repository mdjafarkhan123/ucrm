# Icon tile hairline edge — 2026-10-20

Approved board `k4k5Na`. Every meaning-colour icon tile is now `ui/IconTile`, with a 1px
`--color-<meaning>--surface-edge` border on the plain surface fill (dark mode: edge falls back to the tile colour).
Sizes 20 / 24 / 32 / 40 (`icon-shapes.md`).

Checks: Playwright, owner login, 1440 light and dark, on Home, a job, a client, a payment, Schedule and eight
Settings pages (alerts, automation, forms, taxes, SMS, balance, checklists, pipeline). No page errors and no
sideways scroll on any of them. Screenshots here are a sample (`<page>-<theme>.png`).
`svelte-check --threshold error`: 10 errors, all already on main; none from this change. No lint run (Jafar).

## Follow-up: no hand-built tiles left (Jafar, 2026-10-20)

The grey, white and dark-card squares now use `ui/IconTile` too: `white` for a tile on its own colour (banner,
record header, track steps not reached, lock and note tiles), `tone="feature"` on dark money cards, `inactive`
for file and photo spots, record colours on search results. Circles in timelines and upload rings are not tiles
and stay. Checked at 1440 light and dark on Home, search, a job, a client, a payment, setup and five Settings
pages (`grey-*.png`); no page errors, no sideways scroll; type check shows only the 10 errors already on main.
