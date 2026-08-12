# Radios, Checkboxes & Toggles

> Dependencies: `colors.md`, `radius.md`, `shadows.md`

## Checkbox

A checkbox opts a user into a choice. Use it for multi-select sets or a single opt-in decision — a paired on/off setting is a Toggle, and a single pick from discrete options is a Radio.

- **Size:** 20×20px (`--checkbox--size`), `box-sizing: border-box`
- **Radius:** `var(--radius-small)` (4px)
- **Border:** `var(--border-thick)` (2px) solid `var(--color-border--interactive)`
- **Background:** `var(--color-surface)`
- **Label margin:** label text sits `var(--space-small)` (8px) right of the box, `margin-top: var(--space-smallest)` (2px)
- **Hover:** border-color → `var(--color-interactive)`
- **Checked / indeterminate:** border-color + background → `var(--color-interactive)`; icon stays `var(--color-surface)`
- **Icon:** `checkmark` (checked), `minus2` (indeterminate), fill `var(--color-surface)`, centered
- **Focus ring:** `box-shadow: var(--shadow-focus)`, `outline: none`
- **Transition:** `all var(--timing-quick) ease-out` (100ms)
- **Invalid:** border `var(--color-critical)`; checked/invalid background `var(--color-critical)`

The native input is visually hidden (1×1px, clipped) so the styled box replaces it; the label toggles the input and `:focus-visible` paints the ring on the box.

### Disabled Checkbox

- Box background → `var(--color-disabled--secondary)`; icon `opacity: 0` (reads as an empty box)
- Checked / indeterminate: background → `var(--color-disabled)`; icon re-shown
- Label + description text → `var(--color-disabled)`; `cursor: not-allowed`
- No hover, focus ring, or interaction

## Radio

A radio chooses one discrete option from a small set (pair for binary choices, e.g. "Fixed price" vs "Per visit").

- **Size:** 20×20px circle (`--radio-diameter`), `flex-shrink: 0`
- **Radius:** `var(--radius-circle)` (100%)
- **Border:** `var(--border-thick)` (2px) solid `var(--color-border--interactive)`
- **Background:** `var(--color-surface)`
- **Gap to label:** `var(--space-small)` (8px), `align-items: flex-start`
- **Hover:** border-color → `var(--color-interactive)`
- **Checked:** border-color `var(--color-interactive)` with border-width `var(--radio--checked-thickness)` (6px) — the thick ring leaves an 8px `var(--color-surface)` center
- **Focus ring:** `box-shadow: var(--shadow-focus)`, `outline: none`
- **Transition:** `all var(--timing-quick) ease-out` (100ms)

### Disabled Radio

- Circle border → `var(--color-disabled--secondary)`
- Label text → `var(--color-disabled)`, `cursor: not-allowed`
- Checked-disabled: border-color → `var(--color-disabled)` (settings ring turn grey)

### Radio Group

- All options share the same `name`; the group renders `role="radiogroup"` with a single selection.
- **Vertical** (default): options stack full-width; spacing flows from label height + description margins.
- **Horizontal:** `gap: var(--space-base)` (16px) between options.
- When volume of options > 5 (or vertical space is tight) use a Select instead; when every label is 1–2 words use a Chip instead.

## Toggle (Switch)

A single size — 48×24px track with a 16px thumb. Renders `role="switch"` + `aria-checked`; switches are for binary on/off settings only (label limited to ON/OFF).

### Track

- Width: `var(--switch--width)` (48px); height: `calc(var(--switch--width) / 2)` (24px)
- Radius: `var(--switch--pipSize)` (16px)
- Border: `var(--border-thick)` (2px) solid `var(--color-border--interactive)`
- Background (off): `var(--color-inactive--surface)`
- Background (on): `var(--color-interactive)`; on **hover** → `var(--color-interactive--hover)`
- Hover / `:focus-visible` (any state): border-color → `var(--color-interactive)`
- Focus ring: `box-shadow: var(--shadow-focus)`, `outline: none`
- Container: `inline-flex`, `align-items: center`, `overflow: hidden`

### Thumb (pip)

- Size: 16×16px (`var(--switch--pipSize)`), `border-radius: var(--radius-circle)`
- Off: background `var(--color-inactive--onSurface)`, `transform: translateX(2px)` (`--switch-pipOffPosition`)
- On: background `var(--color-surface)`, `transform: translateX(26px)` (`--switch-pipOnPosition`)

### Track icons

- `checkmark` shown when on, `cross` when off — 16px, rendered inside the track on the opposite side of the thumb
- Fill (on): `var(--color-surface)`; fill (off): `var(--color-inactive--onSurface)`

### Transition

- `all var(--timing-base) ease-in-out` (200ms) on the track and thumb.

### Disabled Toggle

| Part            | Off                                | On                                       |
| --------------- | ---------------------------------- | ---------------------------------------- |
| Track           | `var(--color-surface)` bg, `var(--color-disabled)` border | `var(--color-disabled)` bg      |
| Thumb           | `var(--color-disabled)` bg, `var(--color-disabled--secondary)` border | `var(--color-surface)` bg |

- Applies `cursor: not-allowed`; no hover or focus interaction.

## Label + Control Layout

- Wrapper: `display: flex; align-items: flex-start`, `user-select: none`.
- Gap between control and text: `var(--space-small)` (8px) — checkbox via label `margin`, radio via circle `margin-right: 8px`.
- Label: 14px (`var(--typography--fontSize-base)`), `var(--color-text)`, regular (400) weight.
- Helper text: 12px (`var(--typography--fontSize-small)`), `var(--color-text--secondary)`.
  - Radio helper: `margin-top: calc(var(--space-smaller) * -1)` (−4px), `margin-bottom: var(--space-small)` (8px).
  - Indented to clear the control: `padding-left: calc(control-size + var(--space-small))` (28px at 20px controls).

## Checkbox Group (CRM Filter Panel)

- Vertical stack, `var(--space-slim)` (12px) gap between items.
- Group label: 12px (`--typography--fontSize-small`), uppercase, `var(--color-text--secondary)`, `letter-spacing: 0.5px`.
- Divider between groups: 1px `var(--color-border)`, `margin: var(--space-base)` (16px).
- "Select all" + per-item partial state uses the indeterminate checkbox (minus icon).

## Rules

- Every control must have an `id` matched by its label's `htmlFor`/`for`.
- Focus states use `var(--shadow-focus)` (brand focus ring) for each control.
- Disabled states: no hover/focus interaction; text and control colors flip to grey tokens.
- Indeterminate checkbox is reserved for "select all" partial state.