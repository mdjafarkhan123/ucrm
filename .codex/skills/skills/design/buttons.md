# Buttons

> Dependencies: `colors.md`, `radius.md`, `typography.md`

Buttons initiate, complete, reverse, or navigate an action. Place a button near
the content or object it affects.

## Anatomy

- **Label:** Required for a text button. Use a short, clear, verb-first label.
- **Icon:** Optional. It may appear before or after the label. An icon-only
  button must have an accessible label.
- **Layout:** `inline-flex`, centered vertically and horizontally.
- **Box sizing:** `border-box`.
- **Gap:** `var(--space-smaller)` (4px).
- **Minimum height:** 40px for the base size.
- **Border radius:** `var(--radius-base)` (8px).
- **Border:** `var(--border-base)` (1px) using the variation color by default.
- **Font:** `var(--typography--fontFamily-normal)` (Inter, Helvetica, Arial,
  sans-serif).
- **Label weight:** 600 (semi-bold).
- **Line height:** `var(--typography--lineHeight-base)` (1.25).
- **Transition:** `all var(--timing-base) ease-out`.
- **Text decoration:** none.
- **Cursor:** pointer.

Buttons do not use a shadow or pill radius. The only shadow is the shared focus
ring described below.

## Sizes

`base` is the default and should be used for most actions. Use `small` only
when space is constrained and `large` only in spacious interfaces such as a
login form.

| Size  | Minimum height |                                 Label size |                                      Horizontal padding |             Vertical padding |
| ----- | -------------: | -----------------------------------------: | ------------------------------------------------------: | ---------------------------: |
| Small |           32px |  `var(--typography--fontSize-base)` (14px) |                              `var(--space-slim)` (12px) | `var(--space-smaller)` (4px) |
| Base  |           40px |  `var(--typography--fontSize-base)` (14px) |                              `var(--space-base)` (16px) |                            0 |
| Large |           48px | `var(--typography--fontSize-large)` (16px) | `calc(var(--space-base) + var(--space-smaller))` (20px) |                            0 |

## Types

Each variation supports `primary`, `secondary`, and `tertiary` types.

| Type      | Background                       | Border                             | Label and icon                   | Hover/focus background                  |
| --------- | -------------------------------- | ---------------------------------- | -------------------------------- | --------------------------------------- |
| Primary   | `var(--button--color-variation)` | `var(--button--color-variation)`   | `var(--color-surface)`           | `var(--button--color-variation--hover)` |
| Secondary | `var(--color-surface)`           | `var(--color-border--interactive)` | `var(--button--color-variation)` | `var(--color-surface--hover)`           |
| Tertiary  | `var(--color-surface)`           | transparent                        | `var(--button--color-variation)` | `var(--color-surface--hover)`           |

For secondary and tertiary buttons, the label and icon use
`var(--button--color-variation--hover)` on hover and focus. Secondary buttons
also use the variation hover color for their border on hover and focus.

## Variations

The variation sets the semantic action color variables:

| Variation   | `--button--color-variation`        | `--button--color-variation--hover`        | Use for                                                                    |
| ----------- | ---------------------------------- | ----------------------------------------- | -------------------------------------------------------------------------- |
| Work        | `var(--color-interactive)`         | `var(--color-interactive--hover)`         | Starting, completing, confirming, canceling, or reversing workflow actions |
| Learning    | `var(--color-interactive--subtle)` | `var(--color-interactive--subtle--hover)` | Educational, onboarding, or discovery actions                              |
| Subtle      | `var(--color-interactive--subtle)` | `var(--color-interactive--subtle--hover)` | Low-priority actions, dismissals, and secondary navigation                 |
| Destructive | `var(--color-destructive)`         | `var(--color-destructive--hover)`         | Actions that destroy or remove data                                        |

### Work

- **Primary:** Use for the most important action in a view. Use at most one
  primary action per view.
- **Secondary:** Use for alternate or supporting actions, such as going back or
  previewing before sending.
- **Tertiary:** Use for low-emphasis in-context actions, such as editing a
  section or showing more details.

### Learning

Use for onboarding, product tours, feature discovery, and other educational
actions. Apply the same primary, secondary, and tertiary hierarchy as Work.

### Destructive

Use only for real destructive actions. Use a secondary or tertiary destructive
button to open a confirmation step for high-impact or permanent actions. Use a
primary destructive button for the final confirmed action.

### Subtle

Use for visually de-emphasized, low-priority, or non-blocking actions such as
dismissing a modal or opting out. The subtle tertiary type has a transparent
background; its hover and focus background is `var(--color-surface--hover)`.

## States

### Hover, focus, and active

- Hover and focus-visible use the variation hover color.
- Focus-visible and active use `var(--shadow-focus)` and
  `outline: transparent`.
- The focus ring is 4px beyond the element, with a 2px surface-colored buffer.
- Hover, focus, and active use the same surface and border changes defined by
  the selected type.

### Disabled

Avoid disabled buttons when the action can be redesigned to explain or resolve
the blocked condition. When a disabled state is necessary:

- **Background:** `var(--color-disabled--secondary)`.
- **Border:** `var(--color-disabled--secondary)`.
- **Text and icon:** `var(--color-disabled)`.
- **Interaction:** no hover or click behavior; `pointer-events: none` and
  `cursor: not-allowed`.
- **Selection:** `user-select: none`.

### Loading

Show loading only after the user activates an asynchronous action. Loading
prevents repeated activation and communicates that work is in progress.

- Use `aria-busy="true"`.
- Apply animated diagonal stripes with
  `var(--space-larger)` (32px) background-size.
- Use `var(--timing-loading--extended)` for the animation duration.
- The loading cursor is `not-allowed` and the loading layer does not receive
  pointer events.
- Primary loading buttons use a white translucent stripe; secondary and
  tertiary loading buttons use a black translucent stripe.

## Icons

- Icons may stand alone, appear before the label, or appear after the label.
- Use `iconOnRight` for trailing icons.
- Keep the component’s icon size aligned with the button size: small uses the
  small icon size, base uses the base icon size, and large uses the base icon
  size.
- An icon-only button is square: its width equals its size height and its
  horizontal padding is 0.
- Icon-only buttons require an accessible label such as `aria-label`.

`Button` itself takes no icon yet. The one icon-only button that exists as a
component is the pencil below; build any other icon-only control from these
rules until `Button` grows icon support.

## Pencil button

The square edit affordance beside a heading or at the end of a row. Component:
`src/lib/components/ui/PencilButton.svelte`. Preview:
`(app)/dev-preview/pencil-button`.

Reach for it wherever a pencil means "edit this". Never hand-roll another one.

- **Shape:** square per the icon-only rule — `small` is 32×32 with a 16px glyph,
  `base` is 40×40 with a 24px glyph. `small` is the default.
- **Idle:** transparent background, transparent border,
  `var(--color-interactive--subtle)` glyph.
- **Hover and focus:** `var(--color-interactive--subtle--hover)` glyph on
  `var(--color-surface--hover)`; active deepens to
  `var(--color-surface--active)`.
- **Focus ring:** the shared `var(--shadow-focus)` with `outline: transparent`.
- **Variations:** `subtle` (default) for a calm in-context pencil; `work` for the
  green pencil when editing is the block's main action.
- **Variants:** `tertiary` (default, no border); `secondary` keeps
  `var(--color-border--interactive)` for a pencil on a busy surface.
- **Disabled:** follows the shared disabled treatment.
- **Label:** `label` is required. It becomes both the accessible name and the
  hover title, so name the thing being edited: `Edit Riverbend Family Diner`.
- **Navigation:** pass `href` for an edit page so hover preloading applies; pass
  `onclick` only when editing happens in place.

## Width

Use `width: 100%` for a full-width button when the layout requires the action to
span its container.

## Content guidelines

- Use concise, verb-first labels that describe the outcome.
- Prefer 1–3 words; avoid filler, abbreviations, truncation, and ellipses.
- Use title case.
- Avoid vague labels such as “Submit”, “Continue”, “Yes”, or “Okay” when the
  resulting action can be named explicitly.
- In confirmation flows, restate the consequence: `Delete Visit`, `Send
Invoice`, or `Remove Line Item`.
- Use `Go Back` for a clear secondary way to leave a confirmation flow unless
  more context is needed.
