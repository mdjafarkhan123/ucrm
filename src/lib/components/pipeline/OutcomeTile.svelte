<script lang="ts">
	import { formatMoney, type BoardFormatting } from '$lib/pipeline/money';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';

	// The board's own Won/Lost tile: a fixed rolling 30 days, a chevron that says the whole card opens the
	// Sales Outcomes report, matching Jobber's own tiles above the board.
	let {
		label,
		count,
		valueTotal,
		formatting,
		href
	}: {
		label: string;
		count: number;
		/** Absent when this member may not see money. Never rendered as $0.00 for that case. */
		valueTotal?: number | null;
		formatting: BoardFormatting | null;
		href: string;
	} = $props();

	const money = $derived(
		valueTotal !== undefined && valueTotal !== null && formatting
			? formatMoney(valueTotal, formatting)
			: null
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<a class="outcome-tile" {href} aria-label={`View ${label} opportunities from the past 30 days`}>
	<div class="outcome-tile__topline">
		<span>{label}</span>
		<span class="outcome-tile__chevron" aria-hidden="true">{@html chevronRightIcon}</span>
	</div>
	<strong>{count}</strong>
	<small>Past 30 days{money ? ` · ${money}` : ''}</small>
</a>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.outcome-tile {
		display: block;
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: inherit;
		background: var(--color-surface);
		text-decoration: none;

		&:hover {
			border-color: var(--color-border--interactive);
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}
	.outcome-tile__topline {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}
	.outcome-tile__chevron {
		display: inline-flex;
		color: var(--color-text--secondary);

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}
	.outcome-tile:hover .outcome-tile__chevron {
		color: var(--color-heading);
	}
	.outcome-tile > strong {
		display: block;
		margin: var(--space-small) 0 var(--space-smaller);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		line-height: 1;
	}
	.outcome-tile > small {
		display: block;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
</style>
