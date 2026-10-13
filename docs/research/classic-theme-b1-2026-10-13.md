# Classic B1 — approved tokens in the app

The new Classic values are isolated to the Classic shell. The approved `classic.pen` design-system page has
97 `classic2-*` variables: 79 colours, 17 sizes and one font family. The CSS file has all 97 light values
and the 49 dark overrides. An independent read-only comparison against Pencil found no missing, extra or
mismatched values.

`ClassicFrame.svelte` installs those values on the document root while its shell is present. This lets Bits
UI menus and dialogs inherit them after they portal outside the shell. The app renders one selected shell at
a time; when Botanical is selected, the Classic root selector does not match. No old component has been
restyled in B1. B2 and B3 consume these tokens for the approved shell and shared parts.

## Checks

- `npx svelte-kit sync` then `npm run build`: pass. The first build attempt lacked the worktree's generated
  SvelteKit config; the second lacked its local `.env`; both were setup issues and the final build passed.
- Svelte autofixer on `ClassicFrame.svelte`: zero issues or suggestions.
- `node scripts/verify-classic-theme-tokens.mjs`: pass against two local release servers. At 1440px and
  390px, the Classic page reads its approved light and dark background tokens; a portalled account menu
  reads `--classic2-green` and a portalled search dialog reads `--classic2-ink`. The Botanical preview has no
  `--classic2-page` value.
- Screenshots: [Classic light desktop](classic-theme-b1-2026-10-13/classic-1440-light.png),
  [Classic dark desktop](classic-theme-b1-2026-10-13/classic-1440-dark.png),
  [Classic light phone](classic-theme-b1-2026-10-13/classic-390-light.png),
  [Classic dark phone](classic-theme-b1-2026-10-13/classic-390-dark.png), and
  [Botanical preview](classic-theme-b1-2026-10-13/botanical-1440.png).

The screenshots show the old Dashboard appearance, as intended for B1. Existing dark-mode sidebar and
small-action text has weak contrast; B2/B3 own the approved visual replacement and its screen check. This
B1 check establishes token reach and isolation, not completion of the visual redesign.
