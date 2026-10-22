# Shadows

- Cards, tables and the sidebar: no shadow; their edge is the border.
- Main and danger-confirm buttons: `--shadow-button--raised` — a 0 1 2 shadow in the button's dark shade at
  30%, plus a 1px white inner highlight at 20% along the top.
- White buttons (secondary, danger, menu, icon, joined groups): `--shadow-button--key` — a raised key. Light: a
  0 0 1 ring of `--color-heading` at 24%, 0 1 2 at 8%, 0 2 6 at 6%, and a 1px inner shade along the bottom at 6%.
  Dark: 0 1 2 black at 40% and a 1px white inner highlight along the top at 8%. Hover `--shadow-button--key-hover`
  (light: the ring at 30% and a softer lift, 0 2 4 at 10% and 0 4 10 at 8%); pressed `--shadow-button--key-pressed`
  (the ring and a 0 1 2 inner shadow at 12%; dark: inner black at 35%).
- Chips, tabs, value chips and file cards: `--shadow-button` — 0 1 2 `--color-heading` at 8%.
- Menus, popovers, dialogs: `--shadow-base`.
- Toasts and floating bars: `--shadow-high`.
- Focus ring: `--shadow-focus`.
