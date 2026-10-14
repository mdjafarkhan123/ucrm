# B2 — Classic sidebar and top bar

**Stage:** Built and verified; waiting to merge. **Approval:** B2 order and Classic Pencil screens approved 2026-10-13. **Branch:** `codex/classic-b2`; **worktree:** `/home/jafar/Ucrm/.worktrees/classic-b2`. **Reservation:** `d00412698013` (release after integration).

## Built

`ClassicFrame`, `ClassicHeader` and `Sidebar` use the approved `classic2-*` palette, 248px black-green sidebar, 76px collapsed state, page background, 44px header controls and responsive search. Classic hides the four Soon entries; Botanical's sidebar and header remain separate. `Topbar` keeps Botanical's avatar colors while Classic shows white initials on the approved green gradient when no photo exists. The icon-only Add new action has an accessible name. The Classic sidebar guidance uses the same approved values.

## Evidence and limits

- `npm run build` passed after the final avatar fix (41.18s build phase; exit 0). `npx prettier --check src/lib/components/layout/presentations/ClassicHeader.svelte` and `git diff --check` passed. The Svelte autofixer reported no issues for `ClassicHeader.svelte`.
- Playwright on the signed-in branch app checked Classic at 1440px and 390px in light and dark themes. The avatar computes to the green gradient with white text; desktop and phone have no horizontal overflow or browser errors. Sidebar collapse measured 76px. Ctrl+K opens search and focuses its input; the account and notification menus open; the phone drawer opens and Escape closes it with focus returned to its trigger. `Soon` entries are absent.
- Axe found zero issues scoped to the Classic top bar and sidebar at desktop, and to the top bar plus open phone drawer. A whole-page phone scan still finds two serious contrast issues in the existing Dashboard body buttons; those are carried to B3's shared button work. The Settings body remains on its older layout and clips at phone width and enlarged text; Settings layout work belongs to the later Settings stage.
- The private Botanical preview remains visually separate: its header keeps the Botanical surface and border, its avatar remains beige with brown initials, and the search wording is unchanged. Its phone view has no horizontal overflow or browser errors. Screenshots are saved in `/tmp/classic-b2/` on this machine.
- The Add new menu still says “Nothing to create yet”; B2 did not add creation actions.

## Follow-on ownership

The approved “Settings in the main search” addition belongs to the first later Settings stage, alongside the Settings pages and other approved Settings additions. The behavior contract says those pages and additions follow the first version; B2 keeps the existing search control and does not add a second Settings-only search box.

## Next

Integrate this verified slice into current `main` under a separate `main-integration` reservation, preserve any work already present in the main workspace, run the combined checks, push, and release both reservations. B3 (shared cards, buttons, fields and pills) is next after B2 integration.
