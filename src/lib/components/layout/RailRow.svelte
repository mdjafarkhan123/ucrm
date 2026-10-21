<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import type { Snippet } from 'svelte';

	// One row inside a flush side card (`cards.md` → Side card rows): a 32 icon tile, a quiet label above the
	// value, an optional quiet line under it, the amount at the right, then an optional control. A hairline
	// above separates it from the row before.
	let {
		icon,
		label,
		value,
		valueTone = 'default',
		sub,
		amount,
		tone = 'neutral',
		actions,
		children,
		class: className = ''
	}: {
		/** Tabler icon imported with `?raw`. */
		icon?: string;
		label: string;
		value?: string;
		/** `quiet` for nothing set or no access; `warning` for something still waiting on a choice. */
		valueTone?: 'default' | 'quiet' | 'warning';
		/** A quiet line under the value, e.g. where a tax rate comes from. */
		sub?: string;
		/** A money figure at the right, before the actions. */
		amount?: string;
		/** `warning` tints the icon tile for something still waiting on someone. */
		tone?: 'neutral' | 'warning';
		actions?: Snippet;
		/** Extra content under the value, e.g. a status line. */
		children?: Snippet;
		class?: string;
	} = $props();
</script>

<div class={`rail-row ${className}`}>
	{#if icon}
		<IconTile {icon} tone={tone === 'warning' ? 'warning' : 'inactive'} size={32} />
	{/if}
	<div class="rail-row__text">
		<span class="rail-row__label">{label}</span>
		{#if value}
			<span class="rail-row__value rail-row__value--{valueTone}">{value}</span>
		{/if}
		{#if sub}<span class="rail-row__sub">{sub}</span>{/if}
		{#if children}{@render children()}{/if}
	</div>
	{#if amount}<span class="rail-row__amount">{amount}</span>{/if}
	{#if actions}<div class="rail-row__actions">{@render actions()}</div>{/if}
</div>

<style lang="scss">
	.rail-row {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 14px 16px;
		border-top: var(--border-base) solid var(--color-border);

		&__text {
			display: flex;
			min-width: 0;
			flex: 1 1 auto;
			flex-direction: column;
			gap: 2px;
		}

		&__label,
		&__sub {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__label {
			font-weight: 500;
		}

		&__value {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			overflow-wrap: anywhere;

			&--quiet {
				color: var(--color-text--secondary);
			}

			&--warning {
				color: var(--color-warning--onSurface);
			}
		}

		&__amount {
			flex: 0 0 auto;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			font-variant-numeric: tabular-nums;
			white-space: nowrap;
		}

		&__actions {
			display: flex;
			flex: 0 0 auto;
			align-items: center;
			gap: 6px;
		}
	}
</style>
