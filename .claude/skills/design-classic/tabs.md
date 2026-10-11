# Tabs

> Dependencies: `colors.md`, `radius.md`, `typography.md`

Tabs alternate between related views within the same context. Use them when content splits into sub-groups the user opens one at a time. Do not use Tabs for view navigation or as a table of contents.

There is exactly **one** tab style — the underline tab. There are no pill or full-width variants.

## Core Specs

- **Tab label:** `--typography--fontSize-large` (16px), weight **600**, line-height `--typography--lineHeight-large` (1.34), font `--typography--fontFamily-normal` — rendered via `Text size="large" fontWeight="semiBold"`.
- **Tab height:** 40px (hardcoded `--tab--height` — not a space token).
- **Tab padding:** `--space-smaller` (4px) vertical, `--space-small` (8px) horizontal.
- **Tab radius:** `--radius-base` (8px) on the **top two corners only**; bottom corners square (`border-radius: var(--radius-base) var(--radius-base) 0 0`).
- **Tab gap:** `--space-large` (24px) — the list uses `gap`, tabs never touch.
- **Transition:** `all var(--timing-base)` (200ms) ease.
- **Tab button:** `border: none`, `background: var(--color-surface)`, `cursor: pointer`.
- **Divider:** one bottom border on the tab list row, never on the tabs: `border-bottom: var(--border-base) solid var(--color-border)` (1px). The row pulls itself down `calc(-1 * var(--border-base))` so the divider sits flush with the content edge.
- **Insets:** wrapper and panel share `--public-tab--inset` (defaults to `--space-base`, 16px) on the horizontal axis; the panel's vertical inset is `--tab--vertical-inset` = `--space-base` (16px).

## Structure

```
div (tabs)                       width: 100%; --tab--height: 40px; --tab--vertical-inset: var(--space-base)
└── div (overflow)               position: relative; padding-inline: var(--public-tab--inset)
    ├── ::before / ::after       scroll-edge fades (only when overflowing)
    └── ul[role="tablist"]       display: flex; gap: var(--space-large); overflow-x: auto;
                                 border-bottom: var(--border-base) solid var(--color-border);
                                 margin-bottom: calc(-1 * var(--border-base))
        └── li[role="presentation"]   display: flex; position: relative; list-style: none;
                                      flex: 0 0 fit-content
            └── button[role="tab"]    height: 40px; padding: var(--space-smaller) var(--space-small);
                                      border-radius: var(--radius-base) var(--radius-base) 0 0;
                                      color: var(--color-text--secondary);
                                      background: var(--color-surface)
                └── span              16px / 1.34 / 600
section[role="tabpanel"]         padding: var(--tab--vertical-inset) var(--public-tab--inset)
```

## States

| State              | Tab text                  | Indicator / background                                   |
| ------------------ | ------------------------- | -------------------------------------------------------- |
| Default            | `--color-text--secondary` | none                                                     |
| Hover              | `--color-heading`         | —                                                        |
| Focus (mouse)      | `--color-heading`         | —                                                        |
| Focus-visible (kb) | `--color-heading`         | background `--color-surface--hover`, transparent outline |
| Active             | `--color-heading`         | 4px underline in `--color-interactive`                   |

- The active indicator is a `::after` strip: `position: absolute; left/right: 0; bottom: 0; height: var(--space-smaller)` (4px), `background: var(--color-interactive)` — it spans the full tab width at the bottom edge and sits over the row divider.
- There is **no disabled state** on tabs.
- Colors adapt automatically in dark mode through the token layer — there are no per-state dark overrides.

## Overflow & horizontal scroll

- The tab list scrolls horizontally (`overflow-x: auto`, `-webkit-overflow-scrolling: touch`).
- When content overflows, a fade strip appears on the scrolling edge(s): 24px wide (`--space-large`), full height, `z-index: var(--elevation-base)` (1), `box-shadow: inset -16px 0 16px -16px rgba(var(--color-black--rgb), 0.25)` for the right edge — mirrored (`inset 16px 0 16px -16px`) for the left.

## Keyboard & accessibility

- `ul[role="tablist"]`, `button[role="tab"]`, `section[role="tabpanel"]` with `aria-label` set to the active tab's label.
- `tabIndex` is `0` on the active tab, `-1` on the rest.
- **← / → arrow keys** move focus and activate the adjacent tab; navigation wraps from last to first.
- Known concern: direct Tab-key entry from the selected tab into its panel content is not supported.

## Label content

- Labels are plain text by default and automatically get the 16px / weight-600 typography.
- Non-text labels (custom content — e.g. an `Icon` or a count `InlineLabel`) render as-is, without the default typography.
- Do **not** put interactive elements (e.g. Buttons) inside a tab label.

## Rules

- Underline tabs only — no pill or full-width tab styles.
- Never add borders or shadows to the tab buttons themselves.
- Keep the 24px gap; tabs never stretch (`flex: 0 0 fit-content` on `li`, `flex: 0 0 auto` on the button).
