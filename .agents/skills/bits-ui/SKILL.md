---
name: bits-ui
description: "Build or edit Svelte controls that need an accessible complex interaction: dialogs, confirmation dialogs, tabs, menus, selects, comboboxes, popovers, tooltips, accordions, or calendar controls. Use the installed Bits UI primitives and project styling."
---

# Bits UI

Use Bits UI for complex interaction patterns. Keep simple controls native.

## Workflow

1. Inspect existing wrappers in `src/lib/components/ui` before adding another.
2. Verify the installed API from `node_modules/bits-ui` or current official Bits UI documentation.
3. Use Svelte 5 runes and style the primitive with component-scoped SCSS and semantic tokens.
4. Preserve the primitive's focus management and keyboard behavior. Validate the finished Svelte file with the Svelte autofixer.

## Patterns

- Tabs: use `Tabs.Root`, `Tabs.List`, `Tabs.Trigger`, and `Tabs.Content`. Bind `value` when the current tab must be controlled. Use the project underline-tab styling and retain the primitive's keyboard navigation.
- Destructive or high-impact confirmation: use `AlertDialog.Root`, `Trigger`, `Portal`, `Overlay`, `Content`, `Title`, `Description`, `Cancel`, and `Action`. Keep the final action explicit and show the consequence in the description.
- Ordinary modal: use `Dialog` only when its form or content is not a confirmation.

## Boundaries

- Use `Button` or `AlertDialog.Trigger` with render delegation when the trigger must preserve the shared button appearance.
- Use a portal and overlay for modal layers. Do not recreate focus trapping, Escape behavior, or ARIA wiring by hand.
- Do not expose a disabled or simulated action as a successful mutation. Label it unavailable until its secure API exists.