# Modals

> Dependencies: `colors.md`, `radius.md`, `shadows.md`, `buttons.md`, `inputs.md`

## Core Specs

### Overlay (Backdrop)

- Fixed, covers full screen
- Z-index: `1001` (`--elevation-modal`)
- Background: `rgba(0, 0, 0, 0.32)` (`--color-overlay`)
- Opacity animates from `0` to `0.8` on open, `0` on close, `0.2s` duration

### Content Container

- Background: `var(--color-surface)`
- Border: `var(--border-base) solid var(--color-border)`
- Border-radius: `var(--modal--border-radius)` = `var(--radius-base)` = 8px
- Shadow: `var(--shadow-base)`
- Max-width: `var(--modal--width)` = 600px (default)
- Max-height: `calc(100dvh - 2 * var(--space-base))`
- Margin: `auto`
- Padding: `var(--modal--padding)` = 16px (default), 24px (tablet and up)

## Sizes

| Size | Max-width | Padding |
|------|-----------|---------|
| Default | 600px | 16px (mobile) / 24px (tablet+) |
| Small | 400px | 16px (mobile) / 24px (tablet+) |
| Large | 940px | 16px (mobile) / 24px (tablet+) |
| FullScreen | 100dvw | 0 |

FullScreen removes border-radius and margin, sets height to `100dvh`.

## Anatomy

### Header

- Display: flex, space-between
- Padding: `var(--modal--padding)` = 16px / 24px
- Background: transparent
- Close button: `ButtonDismiss`, padding `calc(var(--base-unit) / 4)` = 4px, margin `-6px -6px`
- Title: `Heading` level 2, id `ATL-Modal-Header`

### Body

- Display: flex, flex-direction: column
- Padding: `var(--space-small)` = 8px
- Overflow-y: auto
- Max-height: inherit
- Text: 16px, `--color-text`

### Actions (Footer)

- Display: flex, justify-content: flex-end
- Padding: `var(--modal--padding)` with `padding-top: 0`
- Buttons gap: `var(--space-small)` = 8px
- Primary + secondary buttons on the right (primary first, then secondary), tertiary on the left

### Sticky Variant

- Header: `variant="sticky"` — pinned to top with 24px fade (`--modal--sticky-region-fade-size`)
- Actions: `variant="sticky"` — pinned to bottom with 24px fade
- Sticky regions require `Modal.Header` and `Modal.Actions` as direct children of `Modal.Content`

## Variants

### Default

Standard header + body + footer with primary/secondary action buttons.
Padding: 16px mobile / 24px tablet+.

### Small

Reduced width (400px). Same internal layout.

### Large

Wider width (940px). Same internal layout.

### FullScreen

- Width: 100dvw
- Max-height: 100dvh
- Margin: 0
- Border-radius: 0
- Dismiss button remains visible

### Confirmation

- `dismissible: false` (no header close button)
- Confirmation button: `type: "primary"`, `variation: "work"` (default) or `"destructive"`
- Cancel button: `type: "primary"`, `variation: "subtle"`
- Variant: `work` (default) or `destructive`
- Supports `size: "small" | "large"` (mapped from Modal sizes)
- Keyboard shortcuts: `Enter` confirms, `Escape` cancels
- Body content: `Content` + `Markdown` for message prop, or children

## Component Structure

### Modal.Provider

- `Modal.Provider` wraps content, provides context
- `Modal.Header` — title + dismiss button (when not custom)
- `Modal.Content` — body wrapper
- `Modal.Actions` — action buttons
- `Modal.Activator` — focus return target

### Accessibility

- `role="dialog"`, `aria-modal="true"`
- Named via `aria-labelledby` when title present, referencing `ATL-Modal-Header`
- Fallback to `ariaLabel` when no title
- Focus trap enabled when open
- Focus returns to activator element on close
- Focus order: floating then content

## Rules

- Overlay covers full screen with fixed positioning
- Content: `var(--color-surface)` background, `var(--radius-base)` border-radius, `var(--shadow-base)`
- Modal z-index: `var(--elevation-modal)` = 1001
- Padding uses `var(--modal--padding)` tokens (16px mobile, 24px tablet+)
- Header and Actions separated by zero top padding on actions
- Close button: `ButtonDismiss` with 4px padding, -6px margin
- ConfirmationModal sets `dismissible: false`
- ConfirmationModal button order: primary then secondary on right, tertiary on left
- Sticky regions require direct children of `Modal.Content`
- Dark mode: tokens automatically invert via `data-theme="dark"`
