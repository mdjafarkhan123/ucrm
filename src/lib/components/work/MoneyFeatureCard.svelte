<script module lang="ts">
	export type MoneyBreakdownPart = {
		label: string;
		/** The figure to show, already formatted. */
		value: string;
		/** How much of the whole bar this part fills; only the proportions between parts matter. */
		share: number;
		tone: 'critical' | 'neutral';
	};
	/** A pill beside the big figure saying how it moved, e.g. "4 more than the 30 days before". */
	export type MoneyTrend = { direction: 'up' | 'down' | 'flat'; label: string };
	export type MoneyDetail = { label: string; value: string };
</script>

<script lang="ts">
	import trendingUpIcon from '@tabler/icons/outline/trending-up.svg?raw';
	import trendingDownIcon from '@tabler/icons/outline/trending-down.svg?raw';
	import minusIcon from '@tabler/icons/outline/minus.svg?raw';

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
		trend,
		details,
		progress,
		loading = false
	}: {
		eyebrow: string;
		value: string;
		note?: string;
		detailLabel?: string;
		detailValue?: string;
		/** Instead of one detail row: a split bar with a legend row for each part. */
		breakdown?: MoneyBreakdownPart[];
		trend?: MoneyTrend | null;
		/** Several label/value rows below the hairline, in place of the single detail row. */
		details?: MoneyDetail[];
		/** A thin bar over the detail rows, filled to this share (0 to 1). */
		progress?: number | null;
		loading?: boolean;
	} = $props();

	const trendIcons = { up: trendingUpIcon, down: trendingDownIcon, flat: minusIcon };
	const progressPercent = $derived(
		progress === null || progress === undefined
			? null
			: Math.round(Math.min(1, Math.max(0, progress)) * 100)
	);
</script>

<section class="money-card" aria-label={eyebrow} aria-busy={loading}>
	<p class="money-card__eyebrow">{eyebrow}</p>
	<div class="money-card__figure">
		<div class="money-card__figure-row">
			<p class="money-card__value">{value}</p>
			{#if trend}
				<p class={['money-card__trend', `money-card__trend--${trend.direction}`]}>
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					<span class="money-card__trend-icon" aria-hidden="true">{@html trendIcons[trend.direction]}</span>
					{trend.label}
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
	{:else if details && details.length > 0}
		<div class="money-card__details">
			{#if progressPercent !== null}
				<div class="money-card__progress" aria-hidden="true">
					<span style:width={`${progressPercent}%`}></span>
				</div>
			{/if}
			<dl class="money-card__legend">
				{#each details as detail (detail.label)}
					<div class="money-card__legend-row">
						<dt>{detail.label}</dt>
						<dd>{detail.value}</dd>
					</div>
				{/each}
			</dl>
		</div>
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
			gap: 6px 10px;
		}
		&__trend {
			display: inline-flex;
			align-items: center;
			gap: 4px;
			margin-bottom: 2px;
			padding: 4px 9px;
			border-radius: 999px;
			color: var(--color-text--reverse);
			background: color-mix(in srgb, var(--color-text--reverse) 8%, transparent);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			line-height: 1.2;
		}
		&__trend-icon {
			display: inline-flex;

			:global(svg) {
				display: block;
				width: 13px;
				height: 13px;
			}
		}
		&__details {
			display: grid;
			gap: var(--space-slim);
			padding-top: 14px;
			border-top: var(--border-base) solid
				color-mix(in srgb, var(--color-text--reverse) 14%, transparent);
		}
		&__progress {
			overflow: hidden;
			height: 6px;
			margin-bottom: 2px;
			border-radius: 3px;
			background: color-mix(in srgb, var(--color-text--reverse) 8%, transparent);

			span {
				display: block;
				height: 100%;
				border-radius: 3px;
				background: var(--color-text--reverse);
			}
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
