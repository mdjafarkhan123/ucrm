# B2 — Classic sidebar and top bar

**Stage:** Done 2026-10-14; integrated into `main`. **Approval:** B2 order and Classic Pencil screens approved 2026-10-13. **Source branch:** `codex/classic-b2`; **worktree:** `/home/jafar/Ucrm/.worktrees/classic-b2`. **Reservations:** B2 `d00412698013` and integration `ab5d6785e5df` (release after push).

## Built

`ClassicFrame`, `ClassicHeader` and `Sidebar` use the approved `classic2-*` palette, 248px black-green sidebar, 76px collapsed state, page background, 44px header controls and responsive search. Classic hides the four Soon entries; Botanical's sidebar and header remain separate. `Topbar` keeps Botanical's avatar colors while Classic shows white initials on the approved green gradient when no photo exists. The icon-only Add new action has an accessible name. The Classic sidebar guidance uses the same approved values.

## Evidence and limits

- `npx svelte-kit sync` generated the fresh integration worktree config, then `npm run build` passed on the combined source (39.27s main build; exit 0). The build reports the existing unused `.job-visits-section` selector and a large client chunk. Prettier, `git diff --check`, and the Svelte autofixer passed for `ClassicHeader.svelte`.
- Playwright on the signed-in branch app checked Classic at 1440px and 390px in light and dark themes. The avatar computes to the green gradient with white text; desktop and phone have no horizontal overflow or browser errors. Sidebar collapse measured 76px. Ctrl+K opens search and focuses its input; the account and notification menus open; the phone drawer opens and Escape closes it with focus returned to its trigger. `Soon` entries are absent. The previous branch pass also checked the owner Control Room at 1440px.
- A live smoke check on the integrated worktree repeated the shell behavior at `http://127.0.0.1:5182/dashboard`: search, notification open/dismiss, 76px collapse, phone drawer Escape/focus return, and no overflow or browser errors.
- Axe found zero issues scoped to the Classic top bar and sidebar at desktop, and to the top bar plus open phone drawer. A whole-page phone scan still finds two serious contrast issues in the existing Dashboard body buttons; those are carried to B3's shared button work. The Settings body remains on its older layout and clips at phone width and enlarged text; Settings layout work belongs to the later Settings stage.
- The private Botanical preview remains visually separate: its header keeps the Botanical surface and border, its avatar remains beige with brown initials, and the search wording is unchanged. Its phone view has no horizontal overflow or browser errors. Screenshots are saved in `/tmp/classic-b2/` on this machine.
- The Add new menu still says “Nothing to create yet”; B2 did not add creation actions.
- The full `npm run check` was not rerun: the previous full check used about 4.9 GB and stayed busy beyond four minutes. Production builds and the component autofixer passed.

## Follow-on ownership

The approved “Settings in the main search” addition belongs to the first later Settings stage, alongside the Settings pages and other approved Settings additions. The behavior contract says those pages and additions follow the first version; B2 keeps the existing search control and does not add a second Settings-only search box.

## Next

B3 (shared cards, buttons, fields and pills) is next. The branch and proof screenshots remain available for review.
