# Buttons

Shared components: src/lib/components/ui/Button.svelte and PencilButton.svelte.

Use the action hierarchy to make the next step clear. Keep the label short and verb-first. An icon-only control needs an accessible name.

## Classic appearance

Use classic2 tokens. Their exact light and dark values are in docs/classic-theme-redesign-design-recipe.md.

| Size | Height | Corners | Use |
| --- | ---: | ---: | --- |
| Small | 30px | 9px | Compact row actions |
| Base | 40px | 12px | Card and page actions |
| Large | 44px | 14px | Spacious header actions |

- Primary: solid brand green with white text and the approved green shadow. Use one main action per page.
- Secondary: surface-soft fill, border-control border and body text.
- Tertiary: surface-soft fill with no border; use for low-emphasis actions.
- Hover and focus use the green hover or green text treatment from the recipe.
- Focus-visible: 3px green-soft outline with a 2px offset.
- Disabled: 45% opacity with no shadow; keep the action unavailable.
- Destructive actions retain the destructive color and confirmation behavior.

PencilButton is a square edit action: 32px small or 40px base. Keep its accessible label and existing link or in-place behavior. Use a resolved href for navigation so SvelteKit can preload the destination.

## Behavior

Use Button for an action, confirmation, or navigation link. Keep loading and disabled behavior. A primary action completes the view's next step; secondary and tertiary actions support it. Do not change labels, permissions or save behavior as part of a visual update.
