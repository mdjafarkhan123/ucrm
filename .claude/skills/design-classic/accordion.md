# Accordion

> Dependencies: `colors.md`, `radius.md`

## Core Specs

- **Wrapper:** full width, 1px border (`--color-border`), `--radius-base` (8px) — clips first/last corners
- **Item separator:** 1px bottom border (`--color-border`) on every item except last

## Trigger (Button)

- **Layout:** flex, space-between, full width
- **Padding:** `--space-large` (24px) horizontal, `--space-base` (16px) vertical
- **Font:** `--typography--fontSize-base` (14px), medium (500)
- **Text:** `--color-text`
- **Background:** `--color-surface--background`
- **Hover:** `--color-surface--background--subtle` background
- **Focus:** no outline; `box-shadow: var(--shadow-focus)`
- **Open state:** `--color-surface--background--subtle` background
- **Transition:** colors `--timing-base`

## Panel (Content)

- **Padding:** `--space-large` (24px) horizontal, `--space-base` (16px) vertical
- **Background:** `--color-surface--background--subtle`
- **Top border:** 1px `--color-border`
- **Font:** `--typography--fontSize-base` (14px), `--color-text--secondary`, `--typography--lineHeight-largest` (1.75)

## Chevron Icon

- Size: 16×16px
- Color: `--color-text--secondary`
- Closed: rotate(0deg)
- Open: rotate(180deg)
- Transition: transform `--timing-base` ease

## Variants

### Default (Collapse)

One panel open at a time. Single shared bordered/rounded wrapper.

### Separated Cards

Each item independent — own 1px border, `--radius-base`, `--shadow-low`. `--space-small` (8px) margin between items. No shared outer wrapper.

### Always Open

Multiple panels can expand simultaneously. Same styling as Default.

### Flush

No outer border. Transparent backgrounds. Only bottom border dividers. Use inside containers that already provide background.

## States

| State    | Trigger appearance                                            |
| -------- | ------------------------------------------------------------- |
| Closed   | `--color-text` text, `--color-surface--background` bg         |
| Open     | `--color-text` text, `--color-surface--background--subtle` bg |
| Hover    | `--color-surface--background--subtle` bg                      |
| Focus    | `--shadow-focus` ring, no outline                             |
| Disabled | `--color-disabled` text, not-allowed cursor                   |

## CRM Usage

- FAQ / Help sections
- Job detail sections (Description, Scope, Materials, Notes)
- Invoice line item groups
- Client contact expandable details
