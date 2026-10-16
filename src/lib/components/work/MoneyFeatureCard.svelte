<script module lang="ts">
	export type MoneyBreakdownPart = {
		label: string;
		/** The figure to show, already formatted. */
		value: string;
		/** How much of the whole bar this part fills; only the proportions between parts matter. */
		share: number;
		tone: 'critical' | 'neutral';
	};
	/** A plain legend row with no bar: a label, an optional count and a figure. */
	export type MoneyFigureRow = {
		label: string;
		count?: string;
		value: string;
	};
</script>

<script lang="ts">
	import trendingUpIcon from '@tabler/icons/outline/trending-up.svg?raw';
	import trendingDownIcon from '@tabler/icons/outline/trending-down.svg?raw';
	import equalIcon from '@tabler/icons/outline/equal.svg?raw';

	// The dark money card beside a work list's overview: one big figure with a line under it, and a
	// second figure below a hairline. It reads from the reverse tokens, so it is dark in the light theme
	// and light in the dark theme.
	let {
		eyebrow,
		value,
		note,
		detailLabel,
		detailValue,
		breakdown,
		rows,
		change,
		loading = false
	}: {
		eyebrow: string;
		value: string;
		note?: string;
		detailLabel?: string;
		detailValue?: string;
		/** Instead of one detail row: a split bar with a legend row for each part. */
		breakdown?: MoneyBreakdownPart[];
		/** Instead of a detail row or a breakdown: plain legend rows under the hairline. */
		rows?: MoneyFigureRow[];
		/** A pill beside the big figure comparing it with the period before. */
		change?: { direction: 'up' | 'down' | 'same'; text: string } | null;
		loading?: boolean;
	} = $props();

	const changeIcons = { up: trendingUpIcon, down: trendingDownIcon, same: equalIcon };
</script>

<section class="money-card" aria-label={eyebrow} aria-busy={loading}>
	<p class="money-card__eyebrow">{eyebrow}</p>
	<div class="money-card__figure">
		<div class="money-card__figure-row">
			<p class="money-card__value">{value}</p>
			{#if change}
				<p class="money-card__change">
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					<span class="money-card__change-icon" aria-hidden="true">{@html changeIcons[change.direction]}</span>
					{change.text}
				</p>
			{/if}
		</div>
		{#if note}<p class="money-card__note">{note}</p>{/if}
	</div>
	{#if breakdown && breakdown.length > 0}
		<div class="money-card__breakdown">
			<div class="money-card__bar" aria-hidden="true">
				{#each breakdown as part (part.label)}
					{#if part.share > 0}
						<span
							class={['money-card__segment', `money-card__segment--${part.tone}`]}
							style:flex-grow={part.share}
						></span>
					{/if}
				{/each}
			</div>
			<dl class="money-card__legend">
				{#each breakdown as part (part.label)}
					<div class="money-card__legend-row">
						<dt>
							<span class={['money-card__swatch', `money-card__segment--${part.tone}`]}></span>
							{part.label}
						</dt>
						<dd>{part.value}</dd>
					</div>
				{/each}
			</dl>
		</div>
	{:else if rows && rows.length > 0}
		<dl class="money-card__legend money-card__legend--ruled">
			{#each rows as row (row.label)}
				<div class="money-card__legend-row">
					<dt>{row.label}</dt>
					<dd class="money-card__figures">
						{#if row.count}<span class="money-card__count">{row.count}</span>{/if}
						<span>{row.value}</span>
					</dd>
				</div>
			{/each}
		</dl>
	{:else if detailLabel}
		<dl class="money-card__detail">
			<dt>{detailLabel}</dt>
			<dd>{detailValue ?? '—'}</dd>
		</dl>
	{/if}
</section>

<style lang="scss">
	.money-card {
		display: flex;
		min-width: 0;
		flex-direction: column;
		justify-content: space-between;
		gap: var(--space-large);
		padding: var(--space-large);
		border-radius: var(--radius-base);
		color: var(--color-text--reverse);
		background: var(--color-surface--reverse);

		&__eyebrow {
			color: var(--color-icon--secondary);
			font-size: 11px;
			font-weight: 700;
			letter-spacing: 1px;
			text-transform: uppercase;
		}
		&__figure {
			display: grid;
			gap: 6px;
		}
		&__figure-row {
			display: flex;
			flex-wrap: wrap;
			align-items: flex-end;
			gap: 10px;
		}
		&__change {
			display: inline-flex;
			align-items: center;
			gap: 4px;
			padding: 4px 9px;
			border-radius: 999px;
			color: var(--color-text--reverse);
			background: color-mix(in srgb, var(--color-text--reverse) 8%, transparent);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
		&__change-icon {
			display: inline-flex;

			:global(svg) {
				display: block;
				width: 13px;
				height: 13px;
			}
		}
		&__legend--ruled {
			gap: 10px;
			padding-top: 14px;
			border-top: var(--border-base) solid
				color-mix(in srgb, var(--color-text--reverse) 8%, transparent);
		}
		&__figures {
			display: inline-flex;
			align-items: center;
			gap: 10px;
		}
		&__count {
			font-weight: 500;
		}
		&__value {
			color: var(--color-text--reverse);
			font-size: 32px;
			font-variant-numeric: tabular-nums;
			font-weight: 700;
			letter-spacing: -1.2px;
			line-height: 1;
			overflow-wrap: anywhere;
		}
		&__note {
			color: var(--color-icon--secondary);
			font-size: 13px;
			font-weight: 500;
		}
		&__breakdown {
			display: grid;
			gap: var(--space-slim);
			padding-top: var(--space-base);
			border-top: var(--border-base) solid
				color-mix(in srgb, var(--color-text--reverse) 14%, transparent);
		}
		&__bar {
			display: flex;
			gap: 3px;
			height: 8px;
		}
		&__segment {
			flex: 1 1 0;
			border-radius: 999px;

			&--critical {
				background: var(--color-critical);
			}
			&--neutral {
				background: var(--color-text--reverse);
			}
		}
		&__legend {
			display: grid;
			gap: var(--space-small);
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
				gap: var(--space-small);
				font-weight: 500;
			}
			dd {
				margin: 0;
				font-variant-numeric: tabular-nums;
				font-weight: 600;
			}
		}
		&__swatch {
			flex: 0 0 8px;
			width: 8px;
			height: 8px;
			border-radius: 999px;
		}
		&__detail {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			margin: 0;
			padding-top: 14px;
			border-top: var(--border-base) solid
				color-mix(in srgb, var(--color-text--reverse) 14%, transparent);
			font-size: 13px;

			dt {
				font-weight: 500;
			}
			dd {
				margin: 0;
				font-variant-numeric: tabular-nums;
				font-weight: 600;
			}
		}
	}
</style>
