# Inputs

Shared fields: src/lib/components/ui/Input.svelte, Select.svelte and Textarea.svelte, with FormField.svelte for an external label and hint.

## Classic appearance

Use classic2 tokens from docs/classic-theme-redesign-design-recipe.md.

- Label above the control: 13px, 600, classic2-body; required marker uses classic2-required.
- Base input and select: 44px high, 12px corners, 1px classic2-border-input, classic2-surface, and the near shadow.
- Text: 14px classic2-ink. Placeholder and help text: classic2-muted.
- Textarea: at least 88px high, 12px corners, 12px vertical and 14px horizontal padding.
- Focus: green border and a 3px classic2-green-soft outline with a 2px offset.
- Invalid: classic2-rose border and error text; preserve the field's alert and description associations.
- Disabled: classic2-surface-soft, classic2-border-input and muted text.
- Select menus are portalled; use the same surface, border, text and shadow tokens as Classic cards and controls.

The label remains above fields in Classic. Do not use the older floating-label appearance.

## Behavior

Keep the visible label associated with its control. Keep hint and error text connected with aria-describedby, preserve aria-invalid and aria-required, and retain the existing validation and disabled states. Placeholders do not replace labels. The design system draws the required marker only when the field blocks saving.
