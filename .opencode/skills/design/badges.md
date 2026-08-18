# Badges

> Dependencies: `colors.md`, `radius.md`,
> See also: `status-indicators.md` for CRM-specific
> Jobber (Atlantis) does not ship a component literally named "Badge". Its badging vocabulary is:

| Component         | Use for                                                    |
| ----------------- | ---------------------------------------------------------- |
| `StatusLabel`     | Status of an item ("Active", "Overdue") — dot + label pill |
| `InlineLabel`     | Generic badging: counts, trends, tags, labels              |
| `StatusIndicator` | A bare status dot (always paired with text)                |
| `Chip`            | Interactive / dismissible / selectable pills               |

## Core Specs

- **Border:** none — badges have no border in Jobber.
- **Radius:** NOT pill. `StatusLabel` → 12px (`0.75rem`); `InlineLabel` small/base → `var(--radius-large)` (16px); `InlineLabel` large/larger → `var(--radius-larger)` (24px); `Chip` → 20px.
- **Font weight:** 600 (semibold).
- **StatusLabel text:** `--typography--fontSize-small` (12px), `line-height: 1` — this keeps the pill exactly **24px tall** (6px padding + 12px text + 6px padding).
- **No `$radius-full` pills.** Pill shape is reserved for avatars and toggle thumbs, not badges.

## Sizes (`InlineLabel`)

| Size   | Text token                       | Font size | Horizontal padding    | Vertical padding         | Radius                   |
| ------ | -------------------------------- | --------- | --------------------- | ------------------------ | ------------------------ |
| small  | `--typography--fontSize-smaller` | 10px      | `--space-small` (8px) | `--space-smallest` (2px) | `--radius-large` (16px)  |
| base   | `--typography--fontSize-small`   | 12px      | 10px                  | 6px                      | `--radius-large` (16px)  |
| large  | `--typography--fontSize-large`   | 16px      | `--space-slim` (12px) | 10px                     | `--radius-larger` (24px) |
| larger | `--typography--fontSize-large`   | 16px      | `--space-base` (16px) | `--space-slim` (12px)    | `--radius-larger` (24px) |

## StatusLabel (status badges)

`StatusLabel` = `StatusIndicator` dot + `Text` label in a pill. Structure:

```
div[role="status"]           display: flex; width: fit-content
                             padding: 6px 10px 6px 8px      (0.375rem 0.625rem 0.375rem 0.5rem)
                             border-radius: 12px            (0.75rem)
                             gap: 6px                       (0.375rem)
                             background: var(--labelBackgroundColor)
├── div (dot wrapper)        padding-top: 2px               (0.125rem — centers dot on text)
│   └── span (dot)           8px × 8px, border-radius: 50%, background: var(--color-{status})
└── Text size="small"        12px, line-height: 1, color: var(--labelTextColor)
```

Only **5 statuses** are allowed. Each sets two internal variables:

| Status        | Background (`--labelBackgroundColor`) | Text (`--labelTextColor`)             | Dot                        |
| ------------- | ------------------------------------- | ------------------------------------- | -------------------------- |
| `success`     | `var(--color-success--surface)`       | `var(--color-success--onSurface)`     | `var(--color-success)`     |
| `warning`     | `var(--color-warning--surface)`       | `var(--color-warning--onSurface)`     | `var(--color-warning)`     |
| `critical`    | `var(--color-critical--surface)`      | `var(--color-critical--onSurface)`    | `var(--color-critical)`    |
| `inactive`    | `var(--color-inactive--surface)`      | `var(--color-inactive--onSurface)`    | `var(--color-inactive)`    |
| `informative` | `var(--color-informative--surface)`   | `var(--color-informative--onSurface)` | `var(--color-informative)` |

- **Alignment:** `start` (dot left) default; `end` flips to `flex-direction: row-reverse` (dot right — used when the pill sits at the end of a row).
- **Accessibility:** `role="status"`; color is never the only signal — always paired with the text label.
- Label should be short (max ~2 words). Long labels wrap; the pill hugs its content.

## InlineLabel Colors (generic badges)

Text / background pairs — all surface-tint patterns, no borders:

| Color                   | Text                                    | Background                          |
| ----------------------- | --------------------------------------- | ----------------------------------- |
| greyBlue (default)      | `var(--color-heading)`                  | `var(--color-inactive--surface)`    |
| red                     | `var(--color-critical--onSurface)`      | `var(--color-critical--surface)`    |
| orange                  | `var(--color-base-orange--600)`         | `var(--color-base-orange--200)`     |
| green                   | `var(--color-success--onSurface)`       | `var(--color-success--surface)`     |
| blue                    | `var(--color-inactive--onSurface)`      | `var(--color-inactive--surface)`    |
| navy / task             | `var(--color-task--onSurface)`          | `var(--color-task--surface)`        |
| yellow / warning        | `var(--color-warning--onSurface)`       | `var(--color-warning--surface)`     |
| lime                    | `var(--color-base-lime--700)`           | `var(--color-base-lime--200)`       |
| purple / invoice        | `var(--color-invoice--onSurface)`       | `var(--color-invoice--surface)`     |
| pink / quote            | `var(--color-quote--onSurface)`         | `var(--color-quote--surface)`       |
| teal                    | `var(--color-base-teal--700)`           | `var(--color-base-teal--200)`       |
| yellowGreen / job       | `var(--color-job--onSurface)`           | `var(--color-job--surface)`         |
| blueDark                | `var(--color-text--reverse--secondary)` | `var(--color-surface--reverse)`     |
| lightBlue / informative | `var(--color-informative--onSurface)`   | `var(--color-informative--surface)` |
| indigo / request        | `var(--color-request--onSurface)`       | `var(--color-request--surface)`     |

In dark mode, `orange`, `lime`, and `teal` invert: text becomes the `--200` shade and background the `--600/--700` shade.

## Badges with Icons / Counts

- Icons are inline children; text renders inside a `<span>` with a fixed line-height (12px at base, 16px at large/larger).
- Use `InlineLabel` for counts and trends (e.g. `<InlineLabel color="red">↓ 15</InlineLabel>`, `<InlineLabel size="larger" color="green">99+</InlineLabel>`).
- For an icon + label pill, use `Chip` with `Chip.Prefix` — the prefix icon sits in a **24×24px circle** (`--space-large`, `--radius-circle`), offset with `margin-left: -8px; margin-right: 8px`.

## Chip (interactive / dismissible badges)

The only dismissible/clickable pill in Jobber — not `StatusLabel`/`InlineLabel`, which are static.

- **Base:** `inline-flex`, `height: 40px` (`--chip-height`), `border-radius: 20px` (`--chip-radius`), `padding: 0 var(--base-unit)` (16px), `border: 1px solid transparent`, text `var(--color-heading)`, background `var(--chip-base-bg-color)`.
- **Subtle variation:** border `var(--color-border--interactive)`, background `var(--color-surface)`, hover background `var(--color-interactive--background)`.
- **Invalid:** border `var(--color-critical)`, background `var(--color-critical--surface)`.
- **Dismiss button (`Chip.Suffix` / `ChipDismissible`):** 24×24px circle (`--space-large` × `--space-large`, `--radius-circle`), `background: var(--color-surface)`, hover `var(--color-surface--hover)`, offset `margin-left: 8px; margin-right: -8px`.
- **Focus:** `var(--shadow-focus)` on the chip and the dismiss button.

## Dot / Status Indicator

`StatusIndicator` — the only dot primitive:

- **Size:** 8×8px (`--space-small`), `border-radius: 50%` (`--radius-circle`), `flex-shrink: 0`.
- **Color:** `var(--color-{status})` — inline style from the 5 statuses above.
- Never used alone for status — pair with text (`StatusLabel` or a label). There is no absolute-positioned notification dot in Atlantis; use it inline only.

## Number Badge (counts)

- Use `InlineLabel`, e.g. size `larger`, color `green` for `99+`.
- There is no separate "count badge" component — counts, trends, and tags are all `InlineLabel`.

## Rules

- Statuses are limited to the 5 `StatusLabel` states — no custom colors for status.
- Never add borders or pill (`$radius-full`) shapes to badges.
- Badges are always `display: inline-flex` / `fit-content` and hug their label.
- Static labels → `StatusLabel`/`InlineLabel`; anything clickable or dismissible → `Chip`.
