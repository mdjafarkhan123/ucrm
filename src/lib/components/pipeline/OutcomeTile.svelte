<script lang="ts">
	import { formatMoney, type BoardFormatting } from '$lib/pipeline/money';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import circleXIcon from '@tabler/icons/outline/circle-x.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';

	// The board's own Won/Lost tile: a fixed rolling 30 days, opening the Sales Outcomes report, matching
	// Jobber's own tiles above the board.
	let {
		label,
		count,
		valueTotal,
		formatting,
		href,
		variant
	}: {
		label: string;
		count: number;
		/** Absent when this member may not see money. Never rendered as $0.00 for that case. */
		valueTotal?: number | null;
		formatting: BoardFormatting | null;
		href: string;
		/** Drives the icon and its color: green check for won, red cross for lost. */
		variant: 'won' | 'lost';
	} = $props();

	const money = $derived(
		valueTotal !== undefined && valueTotal !== null && formatting
			? formatMoney(valueTotal, formatting)
			: null
	);

	const icon = $derived(variant === 'won' ? circleCheckIcon : circleXIcon);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<a
	class={`outcome-tile outcome-tile--${variant}`}
	{href}
	aria-label={`View ${label} opportunities from the past 30 days`}
>
	<span class="outcome-tile__icon" aria-hidden="true">{@html icon}</span>
	<span class="outcome-tile__body">
		<span class="outcome-tile__figure">
			<strong>{count}</strong>
			<span class="outcome-tile__label">{label}</span>
		</span>
		<small>Past 30 days{money ? ` · ${money}` : ''}</small>
	</span>
	<span class="outcome-tile__chevron" aria-hidden="true">{@html chevronRightIcon}</span>
</a>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.outcome-tile {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		padding: var(--space-small);
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
	// Circular badge behind the glyph, tinted by outcome; centered per the icon-shape rules.
	.outcome-tile__icon {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		flex: none;
		width: 32px;
		height: 32px;
		border-radius: var(--radius-circle);

		:global(svg) {
			width: 20px;
			height: 20px;
		}
	}
	.outcome-tile--won .outcome-tile__icon {
		color: var(--color-success);
		background: var(--color-success--surface);
	}
	.outcome-tile--lost .outcome-tile__icon {
		color: var(--color-critical);
		background: var(--color-critical--surface);
	}
	.outcome-tile__body {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		flex: 1;
		min-width: 0;
	}
	// The chevron stays at the far edge and darkens on hover: it is what says the whole tile is a link.
	.outcome-tile__chevron {
		display: inline-flex;
		flex: none;
		color: var(--color-text--secondary);

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}
	.outcome-tile:hover .outcome-tile__chevron {
		color: var(--color-heading);
	}
	.outcome-tile__figure {
		display: flex;
		align-items: baseline;
		gap: 6px;
	}
	.outcome-tile__figure > strong {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		line-height: 1;
		font-variant-numeric: tabular-nums;
	}
	.outcome-tile__label {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}
	.outcome-tile__body > small {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
</style>
