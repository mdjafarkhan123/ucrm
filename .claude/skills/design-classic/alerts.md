# Alerts

> Jobber calls this component **Banner** (the old "Alert" name is retired). For short-lived success feedback, use Toast instead.
> Dependencies: `colors.md`, `radius.md`, `buttons.md`

## Core Specs

- **Padding:** `var(--space-slim) var(--space-base)` = 12px 16px
- **Radius:** `var(--radius-base)` = 8px
- **Border:** none (Banner is borderless — tinted surface only)
- **Message:** plain text, no heading; `var(--typography--fontSize-base)` (14px), normal weight, 1–2 short sentences (<200 chars)
- **Layout:** flex row, `gap: var(--space-small)` (8px) between icon and content, `align-items: center`
- **Background:** `var(--banner-surface)` · **Text:** `var(--banner-textColor)` — both set per variant
- **Role:** `alert` for error type, `status` for all others

## Variants

Jobber's Banner has exactly four types (`success`, `notice`, `warning`, `error`). Each sets a `--surface`/`--onSurface` token pair.

| Type    | Background `--banner-surface`       | Text/Icon color `--banner-textColor`  |
| ------- | ----------------------------------- | ------------------------------------- |
| notice  | `var(--color-informative--surface)` | `var(--color-informative--onSurface)` |
| success | `var(--color-success--surface)`     | `var(--color-success--onSurface)`     |
| warning | `var(--color-warning--surface)`     | `var(--color-warning--onSurface)`     |
| error   | `var(--color-critical--surface)`    | `var(--color-critical--onSurface)`    |

(Base/fallback: `--color-surface` + `--color-text`.)

## Anatomy

- **Icon:** `--typography--fontSize-largest` (24×24px) default-size Icon, left-aligned. Wrapped in a circle: `padding: var(--space-smaller)` (4px), `border-radius: var(--radius-circle)` (100%), background = the **solid** status color, glyph in `var(--color-surface)` (white):
    - notice → `var(--color-informative)` (lightBlue 500)
    - success → `var(--color-success)` (green 600)
    - warning → `var(--color-warning)` (yellow 400)
    - error → `var(--color-destructive)` (red 600)
- **Content:** `flex: 1`, `align-self: center`. Links inherit banner color and are underlined; link hover → `var(--color-heading)`
- **Action (optional):** `flex: 0 0 auto` — use the `primaryAction` prop (a subtle Button), not a raw Button
- **Dismiss (optional):** icon-only ButtonDismiss; `margin: calc(var(--space-smallest) * -1) 0` (−2px 0), `align-self: flex-start`, `mix-blend-mode: multiply` (`screen` in dark theme). Include only when no further user action is required

## Behavior

- Aligns with left/right edges of the content it relates to (text, inputs, other components)
- Remains visible until dismissed or the condition resolves
- Message starts with what's happening, then what's needed; no "Warning:", "Heads up", "FYI", exclamation points, or error codes

## CRM Alert Usage

| Situation                  | Type (Banner) |
| -------------------------- | ------------- |
| Invoice overdue reminder   | warning       |
| Job completed successfully | success       |
| Payment failed / error     | error         |
| New feature announcement   | notice        |
| Permit expiry reminder     | warning       |
| Contract pending signature | notice        |
