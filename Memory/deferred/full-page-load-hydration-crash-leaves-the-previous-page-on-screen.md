# A full page load can crash hydration and leave the previous page on screen

- **Priority:** P2 (was P2; no leak found, no reproduction)
- **Found:** Jobs 15g Round 1 browser pass, 2026-09-08. Console: `Failed to hydrate: HierarchyRequestError`
  reported in `PageHeader.svelte` (a plain header — where it fails, not the cause).
- **Ruled out 2026-09-27:** no cross-user leak — the server redirects a non-owner from `/jafar/*` to
  `/jafar/login` before any Control Room HTML is sent (tested as office). Not reproduced in ~25 full loads
  across `/login`, `/schedule`, `/settings`, `/clients`, `/jafar` on the dev server or the production build
  (`npm run preview`), with no hydration errors in the console. One tab froze, but only a long-lived dev tab
  hit with ten back-to-back loads and no waits.
- **Reactivate when:** anyone sees it again, especially on the production build or the VPS staging rehearsal.
- **Next step then:** capture the console and the exact click sequence first; do not change code on a guess.
