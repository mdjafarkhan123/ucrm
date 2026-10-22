# Batch 63 · Settings home (Control room) — built 2026-10-22

Approved design: Pencil `PZ8xu` (A · Control room). Page: `src/routes/(app)/settings/+page.svelte`.

Checked live at 1440 on the Raad LTD owner (light and dark), the finance role, the search, and a row link.

- `settings-owner-light-1440.png`, `settings-owner-dark-1440.png`: full page.
- `settings-finance-light-1440.png`: a role with fewer permissions sees only the rows it may open; no Ready or balance card.
- `settings-search-tax-1440.png`: typing "tax" narrows the page to the Taxes row.
- Typing a word with no match shows "No settings match"; clicking the Taxes row opens `/settings/taxes`.

Differences from the drawing (all about data the app does not hold yet):
- Desktop alerts switch is a link to My alerts (turning alerts on needs the browser's permission pop-up there).
- The 2-step pill on Security is left out (the app holds no 2-step state yet).
- "Request top-up" opens the balance page, where the request pop-up already lives.
- Ready for customers counts the twelve things in `src/lib/settings/home-ready.ts`; one the member may not open is left out.
