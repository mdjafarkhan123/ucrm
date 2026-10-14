# Segmented Control

Component: src/lib/components/ui/SegmentedControl.svelte.

Use a segmented control for a short choice of two to four labels that fit side by side. Use Select for longer lists. Keep its existing radio-group semantics, checked value, disabled options and change callback.

## Classic appearance

Use classic2 tokens from docs/classic-theme-redesign-design-recipe.md.

- Track: surface-soft, border-control, 12px corners and 3px padding.
- Selected option: surface with the near shadow and ink text.
- Other options: secondary text.
- Base options: 30px high with 9px corners and 12px horizontal padding.
- Small options: 28px high with 8px corners and 10px horizontal padding.
- Focus-visible: 3px green-soft outline with a 2px offset.
- Disabled options use muted text; preserve the disabled track and selection behavior.
