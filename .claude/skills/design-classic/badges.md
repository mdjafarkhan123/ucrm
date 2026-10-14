# Badges

Shared components: src/lib/components/ui/Badge.svelte and StatusBadge.svelte.

Use a status badge for a record state and a plain badge for a short tag, count or category. Keep the text label; color never carries the status by itself.

## Classic appearance

Status pills use 11px bold text, a 6px dot, 5px gap, 3px vertical and 8px horizontal padding, and 10px corners. Use the classic2 tokens from docs/classic-theme-redesign-design-recipe.md.

| Status | Text | Fill | Dot |
| --- | --- | --- | --- |
| success | green | green-soft | green-mid |
| warning | amber | amber-soft | amber-dot |
| critical | rose | rose-soft | rose |
| inactive | secondary | chip | icon-muted |
| informative | blue | blue-soft | blue-dot |

Plain badges use chip fill and body text. Keep badges content-sized and short. Use small or base sizing for tags in compact rows; do not add click behavior to a status badge.
