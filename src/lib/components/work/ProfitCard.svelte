<script lang="ts">
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import trendingUpIcon from '@tabler/icons/outline/trending-up.svg?raw';
	import trendingDownIcon from '@tabler/icons/outline/trending-down.svg?raw';

	// The dark card at the top of a work record's rail: what the work should earn the business. It reads
	// from the reverse tokens, so it is dark in the light theme and light in the dark theme, like the
	// money card on the lists. Every figure arrives already worked out; this card only formats and splits
	// them into cost and profit. The page decides who may see it — it is the business's own numbers.
	let {
		eyebrow = 'Estimated profit',
		costMinor,
		profitMinor,
		revenueMinor,
		marginBasisPoints,
		note,
		currencyCode = 'USD',
		locale = 'en-US'
	}: {
		eyebrow?: string;
		costMinor: number;
		profitMinor: number;
		/** What the work sells for before tax; the bar is cost and profit as shares of it. */
		revenueMinor: number;
		marginBasisPoints: number | null;
		/** The line under the figure. Defaults to a plain statement of the revenue it is measured on. */
		note?: string;
		currencyCode?: string;
		locale?: string;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat(locale, {
			style: 'currency',
			currency: currencyCode,
			maximumFractionDigits: 0
		})
	);
	const format = (minor: number) => money.format(minor / 100);

	const loss = $derived(profitMinor < 0);
	// A bar that cannot be drawn honestly (no revenue, or a loss) shows one full cost segment instead.
	const shares = $derived.by(() => {
		if (revenueMinor <= 0 || loss) return { cost: 100, profit: 0 };
		const cost = Math.min(100, Math.max(0, Math.round((costMinor / revenueMinor) * 100)));
		return { cost, profit: 100 - cost };
	});
	const marginText = $derived(
		marginBasisPoints === null ? null : `${Math.round(marginBasisPoints / 100)}% margin`
	);
	const noteText = $derived(
		note ?? `On ${format(revenueMinor)} of work, after discount, before tax`
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="profit-card" aria-label={eyebrow}>
	<header class="profit-card__header">
		<p class="profit-card__eyebrow">{eyebrow}</p>
		<span class="profit-card__team">
			<span aria-hidden="true">{@html lockIcon}</span>
			Team only
		</span>
	</header>

	<div class="profit-card__figure">
		<div class="profit-card__row">
			<p class="profit-card__value">{format(profitMinor)}</p>
			{#if marginText}
				<span class={['profit-card__margin', loss && 'profit-card__margin--loss']}>
					<span aria-hidden="true">{@html loss ? trendingDownIcon : trendingUpIcon}</span>
					{marginText}
				</span>
			{/if}
		</div>
		<p class="profit-card__note">{noteText}</p>
	</div>

	<div class="profit-card__bar" aria-hidden="true">
		{#if shares.cost > 0}
			<span class="profit-card__segment profit-card__segment--cost" style:flex-grow={shares.cost}
			></span>
		{/if}
		{#if shares.profit > 0}
			<span
				class="profit-card__segment profit-card__segment--profit"
				style:flex-grow={shares.profit}
			></span>
		{/if}
	</div>

	<dl class="profit-card__legend">
		<div class="profit-card__legend-row">
			<dt><span class="profit-card__swatch profit-card__segment--cost"></span>Cost</dt>
			<dd>
				<span class="profit-card__pct">{shares.cost}%</span>
				{format(costMinor)}
			</dd>
		</div>
		<div class="profit-card__legend-row">
			<dt>
				<span class="profit-card__swatch profit-card__segment--profit"></span>
				{loss ? 'Estimated loss' : 'Estimated profit'}
			</dt>
			<dd>
				{#if !loss}<span class="profit-card__pct">{shares.profit}%</span>{/if}
				{format(profitMinor)}
			</dd>
		</div>
	</dl>
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.profit-card {
		display: flex;
		min-width: 0;
		flex-direction: column;
		gap: 20px;
		padding: 24px;
		border-radius: var(--radius-base);
		color: var(--color-text--reverse);
		background: var(--color-surface--reverse);

		&__header {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__eyebrow {
			margin: 0;
			color: var(--color-icon--secondary);
			font-size: 11px;
			font-weight: 700;
			letter-spacing: 1px;
			text-transform: uppercase;
		}

		&__team {
			display: inline-flex;
			align-items: center;
			gap: 5px;
			padding: 4px 9px;
			border-radius: 999px;
			color: var(--color-text--reverse);
			background: color-mix(in srgb, var(--color-text--reverse) 8%, transparent);
			font-size: 12px;
			font-weight: 600;

			:global(svg) {
				display: block;
				width: 11px;
				height: 11px;
				color: var(--color-icon--secondary);
			}
		}

		&__figure {
			display: grid;
			gap: 6px;
		}

		&__row {
			display: flex;
			flex-wrap: wrap;
			align-items: flex-end;
			gap: 10px;
		}

		&__value {
			margin: 0;
			color: var(--color-text--reverse);
			font-size: 32px;
			font-variant-numeric: tabular-nums;
			font-weight: 700;
			letter-spacing: -1.2px;
			line-height: 1;
			overflow-wrap: anywhere;
		}

		&__margin {
			display: inline-flex;
			align-items: center;
			gap: 4px;
			padding: 4px 9px;
			border-radius: 999px;
			color: var(--color-white);
			background: var(--color-interactive);
			font-size: 13px;
			font-weight: 700;

			:global(svg) {
				display: block;
				width: 12px;
				height: 12px;
			}

			&--loss {
				background: var(--color-critical);
			}
		}

		&__note {
			margin: 0;
			color: var(--color-icon--secondary);
			font-size: 13px;
			font-weight: 500;
		}

		&__bar {
			display: flex;
			gap: 3px;
			height: 10px;
		}

		&__segment {
			flex: 1 1 0;
			border-radius: 4px;

			&--cost {
				background: var(--color-warning);
			}
			&--profit {
				background: var(--color-success);
			}
		}

		&__legend {
			display: grid;
			gap: 10px;
			margin: 0;
			font-size: 13px;
		}

		&__legend-row {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);

			dt {
				display: flex;
				align-items: center;
				gap: 8px;
				font-weight: 500;
			}
			dd {
				display: flex;
				align-items: center;
				gap: 8px;
				margin: 0;
				font-variant-numeric: tabular-nums;
				font-weight: 600;
			}
		}

		&__pct {
			color: var(--color-icon--secondary);
			font-weight: 500;
		}

		&__swatch {
			flex: 0 0 8px;
			width: 8px;
			height: 8px;
			border-radius: 2px;
		}
	}
</style>
