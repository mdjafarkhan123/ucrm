# Inputs

> Dependencies: `colors.md`, `radius.md`, `typography.md`

## Core Specs

The field is a flex column wrapper (`border` + `border-radius` + `background` live on the wrapper). The raw `<input>` inside is borderless, transparent, and carries the internal padding.

- **Display:** block, `width: 100%`
- **Height (base size):** `var(--space-largest)` (48px)
- **Radius:** `var(--radius-base)` (8px) on all four corners
- **Border:** `var(--border-base)` (1px) solid `var(--color-border--interactive)` (light blue-grey)
- **Background:** `var(--color-surface)`
- **Shadow:** none at rest — the only shadow is the focus ring
- **Text:** `--typography--fontSize-base` (14px), `line-height: 20px` (`calc(var(--base-unit) * 1.25)`), color `var(--color-heading)`, font-family and font-size inherited from the wrapper
- **Internal padding:** left/right `var(--space-base)` (16px); top/bottom `calc(var(--space-base) - var(--space-smallest))` (14px)
- **Text align:** left by default (center/right variants exist)
- **Transition:** the label morph animates `all var(--timing-quick)` (100ms); the wrapper itself has no transition

## Sizes

| Size  | Padding horizontal     | Padding vertical                                         | Height                                                    |
| ----- | ---------------------- | -------------------------------------------------------- | --------------------------------------------------------- |
| small | `--space-slim` (12px)  | `--space-small` (8px)                                    | `calc(var(--space-larger) + var(--space-smaller))` (36px) |
| base  | `--space-base` (16px)  | `calc(var(--space-base) - var(--space-smallest))` (14px) | `var(--space-largest)` (48px)                             |
| large | `--space-large` (24px) | 14px                                                     | `var(--space-extravagant)` (64px)                         |

## Label

A floating mini-label: the placeholder text is rendered as a `<label>` whose `htmlFor` matches the input `id`. It starts centered inside the field and shrinks/floats to the top on focus or once a value exists.

- **Position:** `position: absolute`, vertically centered (`offset: 50%`, `transform: translateY(-50%)`), inherits the field's left/right padding
- **Idle:** 14px, color `--color-base-blue--600`, `pointer-events: none`, `white-space: nowrap` + `text-overflow: ellipsis`
- **Floating / mini label** (focused or has value):
    - Color becomes `var(--color-text--secondary)`
    - Moves to the top (`offset: var(--space-smallest)`, `transform: none`)
    - Field padding shifts to `padding-top: calc(var(--space-base) + var(--space-smaller))` (20px), `padding-bottom: var(--space-small)` (8px)
    - Transition: `all var(--timing-quick)` (100ms)
- **Small fields** hide the mini-label instead of floating it (label is `display: none` in that state)
- **External label** (`FormFieldLabel external` above the field): `display: block`, `margin-bottom: var(--space-smaller)` (4px), color `var(--color-base-blue--600)`, `line-height: 1.25`

## States

### Default

- Border: `var(--color-border--interactive)`
- Background: `var(--color-surface)`
- Text: `var(--color-heading)`

### Hover

- **None** — the field has no dedicated hover styling

### Focus / Focus-within

- Input `outline: none`
- Wrapper: `position: relative`, `box-shadow: var(--shadow-focus)` (a 2px `var(--color-surface)` ring inset + 4px `var(--color-focus)` outer ring), lifted above siblings (`z-index: var(--elevation-base)`)
- Border color does **not** change on focus

### Error / Invalid

- Border: `var(--color-critical)`
- Focus ring unchanged (still `--shadow-focus`); the red border persists while focused
- Message below (role `alert`, assertive): `--typography--fontSize-small` (12px) `var(--color-critical)`, `alert` icon 16×16px (icon size `small`), `padding: var(--space-smaller) 0`, slides/fades in over `var(--timing-base)` (200ms)

### Disabled

- Background: `var(--color-disabled--secondary)`
- Border: `var(--color-border)`
- Value and placeholder: `var(--color-disabled)`
- iOS-specific `-webkit-text-fill-color` override sets `opacity: 1` so text isn't faint
- No `cursor` rule is applied

### Success

- **None.** There is no painted success state on the field — the only validation color is `error/invalid`. Use a `status-indicators.md` element for confirmation.

## Prefix & Suffix (affixes)

- Affixes render inside the field row, vertically centered against the field height
- **Icon size:** 24×24px (icon size `base`); small size fields use 16×16px (icon size `small`)
- **Icon color:** `var(--color-greyBlue)`
- An affix icon with an action is wrapped in a subtle/tertiary icon `Button`
- Affix labels keep the field's `line-height` and vertical centering
- Field left/right padding (16px base) is preserved; value text never overlaps the affix

## Clear action

- When `clearable` and the field has a value (and isn't disabled/readOnly), a clear (`cross`) icon appears at the inner end — 16×16px, focusable, aligned with the field's right padding

## Multiline (textarea)

- Same field surface/border; `resize: vertical`, `overflow: auto`
- Default `rows: 3`; `min-height: var(--field--height)`
- Textarea is `flex`-grow and its padding comes from the field vars

## Rules

- Every input must have a unique `id`
- Every label must have a matching `htmlFor` (generated automatically in the floating label)
- Use tokens — never hardcoded hex or arbitrary colors
- Focus is expressed only with `--shadow-focus` (no outline, no border swap)
- The only field "error" color is `--color-critical` for `invalid`/error
