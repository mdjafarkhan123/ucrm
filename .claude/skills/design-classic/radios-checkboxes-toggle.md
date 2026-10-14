# Radios, Checkboxes and Toggles

Shared components: src/lib/components/ui/RadioGroup.svelte, Checkbox.svelte and Toggle.svelte.

## Classic appearance

Use classic2 tokens from docs/classic-theme-redesign-design-recipe.md.

### Checkbox

- 20px square, 6px corners, classic2-border-input border and surface fill
- Checked and indeterminate: solid-green fill, white icon
- Focus-visible: 3px green-soft outline with a 2px offset
- Invalid: rose border; disabled: surface-soft and muted text

### Radio

- 20px circle with classic2-border-input border
- Selected: green border
- Focus-visible: 3px green-soft outline with a 2px offset
- A cards variant uses surface, border and green selection tint

### Toggle

- 44px by 26px track with a 20px thumb and 13px corners
- Off: surface with border-input; on: green-mid with a white thumb
- Focus-visible: 3px green-soft outline with a 2px offset
- A disabled toggle stays muted and unavailable

Labels use 14px body text. Descriptions use 12px muted text. Keep the current native input, keyboard use, accessible name, disabled state and callback behavior.
