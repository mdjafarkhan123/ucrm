# Classic sidebar and top bar

The approved source is `Settings · Home · 1440` in `classic.pen` and § Page and shell of
`docs/classic-theme-redesign-design-recipe.md`. The implementation is `Sidebar.svelte`,
`ClassicHeader.svelte` and `ClassicFrame.svelte`. This page describes B2's built shell; use the recipe's
`classic2-*` names for exact colour values.

## Sidebar

- At desktop width, the shell has a 12px outside edge, a 248px sidebar and a 20px gap before content.
  The sidebar has a 24px radius, 18px/14px/16px/14px padding and a `sidebar-top` to `sidebar` black-green
  gradient. Its border uses `sidebar-edge`, visible in dark mode.
- The 40px logo sits in a 60px brand block. Use the business's saved logo and name where available; the
  fallback mark uses `logo-start` and `solid-green`. The collapse control keeps its label for screen readers.
- Group labels are 11px uppercase `sidebar-group`. Navigation rows are 38px high with 18px neutral icons,
  14px labels and a 12px radius. The active row uses `sidebar-active` with white text and icon. Counts show
  as pills. Settings is pinned below the groups when space allows. Entries marked Soon stay hidden in Classic.
- Collapsed width is 76px: icons and counts remain, labels become link titles/accessible names. On phones
  under 768px the sidebar becomes the existing modal navigation drawer. Escape and the backdrop close it;
  focus returns to the opener. The same Classic colours and visible menu items apply there.

## Top bar

- The Classic top bar sits on the page background without a card. Its search is at most 440px wide and 44px
  high, with `surface`, `border-control`, 14px radius, a search icon and the Ctrl K hint. It keeps the main
  search interaction and keyboard shortcut. When space is tight, the search takes its own phone row.
- The right side holds the existing appearance control, notification bell, green Add new button and 44px
  round account avatar. Icon buttons are 44px bordered `surface` squares with a 14px radius. Preserve the
  controls' real actions, menus, permissions and focus handling while restyling them.
- Use `classic2-page` for the frame background. Keep the selected presentation boundary in `ClassicFrame`;
  Botanical has its own sidebar and header styles.
