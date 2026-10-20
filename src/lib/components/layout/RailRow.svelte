<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import type { Snippet } from 'svelte';

	// One row inside a flush rail card (App look): a small icon tile, a quiet label above and the value
	// below, with an optional control at the far end. A hairline above separates it from the row before.
	let {
		icon,
		label,
		value,
		tone = 'neutral',
		actions,
		children,
		class: className = ''
	}: {
		/** Tabler icon imported with `?raw`. */
		icon?: string;
		label: string;
		value?: string;
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
		{#if value}<span class="rail-row__value">{value}</span>{/if}
		{#if children}{@render children()}{/if}
	</div>
	{#if actions}<div class="rail-row__actions">{@render actions()}</div>{/if}
</div>

<style lang="scss">
	.rail-row {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 12px 20px;
		border-top: var(--border-base) solid var(--color-border);

		&__text {
			display: flex;
			min-width: 0;
			flex: 1 1 auto;
			flex-direction: column;
			gap: 2px;
		}

		&__label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}

		&__value {
			color: var(--color-heading);
			font-size: 13px;
			font-weight: 600;
			overflow-wrap: anywhere;
		}

		&__actions {
			display: flex;
			flex: 0 0 auto;
			align-items: center;
			gap: 6px;
		}
	}
</style>
