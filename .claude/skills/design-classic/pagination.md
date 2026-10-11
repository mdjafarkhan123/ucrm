# Pagination

> Dependencies: `colors.md`, `radius.md`, `buttons.md`, `inputs.md`, `typography.md`

Pagination is the **table footer** control for paging through data rows. There are **no page-number buttons** ("1 2 3 4") anywhere in the vocabulary — paging is always a summary bar made of three parts:

1. **Info text** — "Showing {first}-{last} of {total} items"
2. **Per-page selector** — a small `<select>` + "per page" label
3. **Round-trip buttons** — Previous / Next icon buttons

It exists in two flavors:

- **Built-in bar** — all three parts bundled, auto-driven.
- **Composable** — a bare `Pagination` container + `PaginationButton` pair you place yourself.

## Placement

- Sits **below the `<table>`** (and below any `<tfoot>`/footer) as the last row of the table container — it is **never** placed inside the footer.
- Footer row is for column-aligned content (totals); pagination is the navigation row and lives outside the table element.

## Built-in bar

### Container

Flex row that spreads the summary text left and the controls right, wrapping on narrow screens:

| Property        | Value                                                          |
| --------------- | -------------------------------------------------------------- |
| Layout          | `display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap` |
| Gap             | `var(--space-small)` (8px)                                    |
| Min height      | `calc(var(--space-smaller) + var(--space-larger))` (52px)     |
| Padding         | `var(--space-small) var(--space-base)` (8px 16px)            |
| Border          | `var(--border-base)` solid `var(--color-border)` — **top only** (it sits on the table's bottom edge) |

### Info text

- Plain `Text` — `var(--typography--fontSize-base)` (14px), weight 400, `var(--color-text)`.
- Renders exactly: `Showing {first}-{last} of {total} items` (e.g. "Showing 11-20 of 42 items").
- `flex: 9999; white-space: nowrap` — absorbs the free space so the nav cluster is pushed to the right edge.
- **Loading:** replaced by a shimmer placeholder (200px wide).
- **Empty (0 rows):** shows only "No items" — no selector, no buttons.

### Nav cluster

`display: flex; align-items: center; justify-content: space-between; gap: var(--space-base)` (16px); `flex: 1; flex-wrap: wrap; min-width: fit-content`.

Three children:

1. **Per-page select** — a small form-field `<select>` (page-size input):
   - Options default to `10 / 20 / 30 / 40 / 50`; default page size **10**.
   - `min-width: calc(3 * var(--space-largest) + var(--space-small))` (152px) so three option digits always fit.
2. **"per page" label** — `<span>` after the select, `min-width: calc(var(--space-extravagant) + var(--space-smaller))` (68px).
3. **Buttons** (`Previous` / `Next`) — see below.

### Buttons

Previous / Next are **icon-only secondary buttons**, 40×40px (base size), gap between them `var(--space-large)` (24px), centered.

- **Border:** 1px solid `var(--color-border--interactive)`.
- **Icon:** `arrowLeft` / `arrowRight`, 24px, fill `var(--color-interactive--subtle)`.
- **Hover:** fill + border `var(--color-interactive--subtle--hover)`, background `var(--color-surface--hover)`.
- **Focus:** `var(--shadow-focus)` (`box-shadow: 0 0 0 2px var(--color-surface), 0 0 0 4px var(--color-focus)`, `outline: transparent`).
- **Disabled:** previous at page 1, next at last page — Button's disabled state.
- **A11y:** each button carries an `aria-label` of "Previous page" / "Next page".
- On `max-width: 489px` (and the small-screen breakpoint) the inter-button gap compresses to `var(--space-base)` (16px).

## Composable API

- **`Pagination`** — bare container (identical frame to the built-in bar):
  - `padding: var(--space-small) var(--space-base)` (8px 16px)
  - `border-top: var(--border-base)` solid `var(--color-border)`
  - Children are your own controls.
- **`PaginationButton`** — pre-wired Previous/Next button:
  - Same base button as the built-in bar, but the **learning** accent (which resolves to the same `var(--color-interactive--subtle)` as subtle).
  - `direction: "previous" | "next"` picks `arrowLeft` / `arrowRight`; supports `disabled` and a required `onClick`.
  - `ariaLabel` **required** — a function of `direction` returning translated "Previous page" / "Next page".

## Rules

- Never render page-number pills (`1 2 3 …`); paging is previous/next plus a "Showing X-Y of Z" summary and a per-page picker.
- Pagination always sits **outside** the table and footer, inside the container.
- The info text is the visual separator — it must stay on the left, controls on the right (`flex: 9999` handles this even when wrapping).
- Buttons are icon-only: they require an `aria-label`; never add labels/text to the arrow buttons.
- Colors are token-driven (`var(--color-border)`, `var(--color-interactive--subtle)`, `var(--color-surface--hover)`) — they re-resolve in dark mode, no special-casing needed.