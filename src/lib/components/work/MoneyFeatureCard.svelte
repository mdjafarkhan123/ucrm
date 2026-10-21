<script module lang="ts">
	export type MoneyBreakdownPart = {
		label: string;
		/** The figure to show, already formatted. */
		value: string;
		/** How much of the whole bar this part fills; only the proportions between parts matter. */
		share: number;
		tone:
			| 'critical'
			| 'neutral'
			| 'success'
			| 'muted'
			| 'items'
			| 'expenses'
			| 'labor'
			| 'profit'
			| 'loss';
		/** A quiet share figure before the value, e.g. "54%". */
		percent?: string;
	};
	/** A plain legend row with no bar: a label, an optional count and a figure. */
	export type MoneyFigureRow = {
		label: string;
		count?: string;
		value: string;
	};

	export type MoneyDetailRow = { label: string; value: string };
</script>

<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import type { Snippet } from 'svelte';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import trendingUpIcon from '@tabler/icons/outline/trending-up.svg?raw';
	import trendingDownIcon from '@tabler/icons/outline/trending-down.svg?raw';
	import equalIcon from '@tabler/icons/outline/equal.svg?raw';

	// The green money card beside a work list's overview: one big figure with a line under it, and a
	// second figure below a hairline. It is the screen's one feature card, so it reads from the feature
	// tokens and stays the same deep green in light and dark themes.
	let {
		eyebrow,
		value,
		note,
		detailLabel,
		detailValue,
		breakdown,
		rows,
		progress,
		change,
		icon,
		badge,
		badgeIcon,
		pill,
		details,
		children,
		record = false,
		summary = record,
		emptyBar = false,
		loss = false,
		footnote,
		loading = false
	}: {
		eyebrow: string;
		/** Leave out for a card that is only a list of figures. */
		value?: string;
		note?: string;
		detailLabel?: string;
		detailValue?: string;
		/** Instead of one detail row: a split bar with a legend row for each part. */
		breakdown?: MoneyBreakdownPart[];
		/** Instead of a detail row or a breakdown: plain legend rows under the hairline. */
		rows?: MoneyFigureRow[];
		/** A thin bar over the plain rows, filled to this share (0 to 1). */
		progress?: number | null;
		/** A pill beside the big figure comparing it with the period before. */
		change?: { direction: 'up' | 'down' | 'same'; text: string } | null;
		/** A Tabler icon (raw SVG) on a soft tile before the eyebrow, naming what the money is. */
		icon?: string;
		/** A small chip at the end of the eyebrow row, e.g. "Due in 7 days". */
		badge?: string;
		/** A Tabler icon (raw SVG) drawn in the chip. */
		badgeIcon?: string;
		/** A green pill beside the figure, e.g. "54% paid". */
		pill?: string;
		/** More label/value rows under a hairline, below the breakdown. */
		details?: MoneyDetailRow[];
		/** Extra content at the foot of the card, such as an inset call to action. */
		children?: Snippet;
		/** The record-page rail version: the breakdown sits straight under the figure and the hairline moves
		 *  above the extra rows. */
		record?: boolean;
		/** Approved ink-blue money summary, shared by job, quote and invoice records. */
		summary?: boolean;
		emptyBar?: boolean;
		loss?: boolean;
		/** A quiet line at the very foot, e.g. "Updates as you add or change lines." */
		footnote?: string;
		loading?: boolean;
	} = $props();

	const changeIcons = { up: trendingUpIcon, down: trendingDownIcon, same: equalIcon };
	const progressPercent = $derived(
		progress === null || progress === undefined
			? null
			: Math.round(Math.min(1, Math.max(0, progress)) * 100)
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section
	class={[
		'money-card',
		record && 'money-card--record',
		summary && 'money-card--summary',
		loss && 'money-card--loss'
	]}
	aria-label={eyebrow}
	aria-busy={loading}
>
	<div class="money-card__head">
		<div class="money-card__top">
			<div class="money-card__title">
				{#if icon && !summary}<IconTile {icon} tone="feature" size={32} />{/if}
				<p class="money-card__eyebrow">{eyebrow}</p>
			</div>
			{#if badge}
				<span class="money-card__badge">
					{#if badgeIcon}<span class="money-card__badge-icon" aria-hidden="true"
							>{@html badgeIcon}</span
						>{/if}
					{badge}
				</span>
			{/if}
		</div>
		{#if value !== undefined || note}
			<div class="money-card__figure">
				<div class="money-card__figure-row">
					{#if value !== undefined}<p class="money-card__value">{value}</p>{/if}
					{#if pill}
						<span class="money-card__pill">
							<span class="money-card__pill-icon" aria-hidden="true">{@html checkIcon}</span>
							{pill}
						</span>
					{/if}
					{#if change}
						<p class="money-card__change">
							<span class="money-card__change-icon" aria-hidden="true"
								>{@html changeIcons[change.direction]}</span
							>
							{change.text}
						</p>
					{/if}
				</div>
				{#if note}<p class="money-card__note">{note}</p>{/if}
			</div>
		{/if}
	</div>
	{#if emptyBar}<div class="money-card__bar" aria-hidden="true">
			<span class="money-card__segment money-card__segment--muted"></span>
		</div>{/if}
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
						<dd class={`money-card__amount--${part.tone}`}>
							{#if part.percent}<span class="money-card__percent">{part.percent}</span>{/if}
							{part.value}
						</dd>
					</div>
				{/each}
			</dl>
		</div>
	{:else if rows && rows.length > 0}
		<div class="money-card__rows">
			{#if progressPercent !== null}
				<div class="money-card__progress" aria-hidden="true">
					<span style:width={`${progressPercent}%`}></span>
				</div>
			{/if}
			<dl class="money-card__legend">
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
		</div>
	{:else if detailLabel}
		<dl class="money-card__detail">
			<dt>{detailLabel}</dt>
			<dd>{detailValue ?? '—'}</dd>
		</dl>
	{/if}
	{#if (details && details.length > 0) || children}
		<div class="money-card__foot">
			{#if details && details.length > 0}
				<dl class="money-card__foot-rows">
					{#each details as row (row.label)}
						<div class="money-card__legend-row">
							<dt>{row.label}</dt>
							<dd>{row.value}</dd>
						</div>
					{/each}
				</dl>
			{/if}
			{#if children}<div class="money-card__inset">{@render children()}</div>{/if}
		</div>
	{/if}
	{#if footnote}<p class="money-card__footnote">{footnote}</p>{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.money-card {
		display: flex;
		min-width: 0;
		flex-direction: column;
		gap: var(--space-large);
		padding: var(--space-large);
		border-radius: var(--radius-large);
		color: var(--color-feature--text);
		background:
			radial-gradient(
				90% 220% at 85% 0%,
				var(--color-feature--glow),
				var(--color-feature--glow-end)
			),
			linear-gradient(200deg, var(--color-feature--start), var(--color-feature--end));

		/* The eyebrow and the big figure sit together at the top; whatever follows is pushed to the foot,
		   so a card stretched to its neighbour's height keeps its figure up where the eye starts. */
		&__head {
			display: grid;
			gap: var(--space-base);
		}
		& > &__head + * {
			margin-top: auto;
		}
		&__title {
			display: flex;
			min-width: 0;
			align-items: center;
			gap: var(--space-slim);
		}
		&__eyebrow {
			color: var(--color-feature--text--secondary);
			font-size: var(--typography--fontSize-overline);
			font-weight: 600;
			letter-spacing: 0.8px;
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
		&__change {
			display: inline-flex;
			align-items: center;
			gap: 4px;
			margin-bottom: 2px;
			padding: 4px 9px;
			border-radius: 999px;
			color: var(--color-feature--text);
			background: var(--color-feature--subtle);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			line-height: 1.2;
		}
		&__change-icon {
			display: inline-flex;

			:global(svg) {
				display: block;
				width: 13px;
				height: 13px;
			}
		}
		&__rows {
			display: grid;
			gap: 10px;
			padding: var(--space-slim) var(--space-base);
			border: var(--border-base) solid var(--color-feature--border);
			border-radius: var(--radius-base);
			background: var(--color-feature--subtle);
		}
		&__progress {
			overflow: hidden;
			height: 6px;
			margin-bottom: 2px;
			border-radius: 3px;
			background: var(--color-feature--border);

			span {
				display: block;
				height: 100%;
				border-radius: 3px;
				background: var(--color-feature--text);
			}
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
			color: var(--color-feature--text);
			font-size: var(--typography--fontSize-display);
			font-variant-numeric: tabular-nums;
			font-weight: 700;
			letter-spacing: -0.6px;
			line-height: 1;
			overflow-wrap: anywhere;
		}
		&__note {
			color: var(--color-feature--text--secondary);
			font-size: 13px;
			font-weight: 500;
		}
		&__breakdown {
			display: grid;
			gap: var(--space-slim);
			padding: var(--space-slim) var(--space-base);
			border: var(--border-base) solid var(--color-feature--border);
			border-radius: var(--radius-base);
			background: var(--color-feature--subtle);
		}
		&__bar {
			display: flex;
			gap: 3px;
			height: 8px;
		}
		/* On green, money in is solid white and money still to come a softer white; the status greens
		   would vanish into the card. */
		&__segment {
			flex: 1 1 0;
			border-radius: 999px;

			&--success {
				background: var(--color-feature--text);
			}
			&--muted {
				background: var(--color-feature--border);
			}
			&--critical {
				background: var(--color-feature--alert);
			}
			&--neutral {
				background: var(--color-feature--text--secondary);
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
		&__percent {
			margin-right: var(--space-small);
			color: var(--color-feature--text--secondary);
			font-weight: 500;
		}
		&__top {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}
		&__badge {
			display: inline-flex;
			align-items: center;
			gap: 5px;
			padding: 4px 9px;
			border-radius: 999px;
			background: var(--color-feature--subtle);
			font-size: 12px;
			font-weight: 600;
		}
		&__badge-icon,
		&__pill-icon {
			display: inline-flex;

			:global(svg) {
				display: block;
				width: 12px;
				height: 12px;
			}
		}
		&__badge-icon {
			color: var(--color-feature--text--secondary);
		}
		&__pill {
			display: inline-flex;
			align-items: center;
			gap: 4px;
			margin-bottom: 2px;
			padding: 4px 9px;
			border-radius: 999px;
			color: var(--color-feature--start);
			background: var(--color-feature--text);
			font-size: 13px;
			font-weight: 700;
		}
		&__foot {
			display: grid;
			gap: 12px;
			padding-top: 14px;
			border-top: var(--border-base) solid var(--color-feature--border);
		}
		&__foot-rows {
			display: grid;
			gap: 12px;
			margin: 0;
			font-size: 13px;

			dd {
				font-weight: 700;
			}
		}
		&__inset {
			display: grid;
			justify-items: start;
			gap: 10px;
			padding: 12px;
			border-radius: var(--radius-base);
			background: var(--color-feature--subtle);
			font-size: 13px;
			font-weight: 500;

			&:empty {
				display: none;
			}
		}
		// The record-page rail version: the split bar sits straight under the figure, with no hairline
		// above it, and the card's rows carry the hairline instead.
		&--record &__breakdown {
			padding: 0;
			border: 0;
			background: none;
		}
		&--record {
			gap: 20px;
			padding: 24px;
		}
		&__footnote {
			color: var(--color-feature--text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		&__swatch {
			flex: 0 0 8px;
			width: 8px;
			height: 8px;
			border-radius: 999px;
		}
		/* One more figure, in a soft panel: its label above, the amount under it. */
		&__detail {
			display: grid;
			gap: 2px;
			margin: 0;
			padding: var(--space-slim) var(--space-base);
			border: var(--border-base) solid var(--color-feature--border);
			border-radius: var(--radius-base);
			background: var(--color-feature--subtle);
			font-size: 13px;

			dt {
				color: var(--color-feature--text--secondary);
				font-weight: 500;
			}
			dd {
				margin: 0;
				font-size: var(--typography--fontSize-larger);
				font-variant-numeric: tabular-nums;
				font-weight: 700;
			}
		}
	}
	.money-card--summary {
		gap: var(--space-medium);
		border: var(--border-base) solid var(--color-money--border);
		background: linear-gradient(200deg, var(--color-money--start), var(--color-money--end));
		.money-card__eyebrow {
			font-size: var(--typography--fontSize-small);
		}
		.money-card__head {
			gap: var(--space-medium);
		}
		.money-card__value {
			font-size: var(--typography--fontSize-stat);
		}
		.money-card__badge {
			border: var(--border-base) solid var(--color-feature--border);
			font-size: var(--typography--fontSize-label);
		}
		.money-card__badge-icon :global(svg) {
			width: 14px;
			height: 14px;
		}
		.money-card__breakdown {
			padding: 0;
			border: 0;
			background: none;
		}
		.money-card__bar {
			height: 10px;
		}
		.money-card__legend,
		.money-card__foot-rows {
			font-size: var(--typography--fontSize-base);
		}
		.money-card__swatch {
			border-radius: var(--radius-small);
		}
		.money-card__pill {
			color: var(--color-money--start);
			background: var(--color-money--profit);
		}
		.money-card__amount--profit {
			color: var(--color-money--profit);
		}
		.money-card__amount--loss {
			color: var(--color-money--loss);
		}
		&.money-card--loss .money-card__pill {
			background: var(--color-money--loss);
		}
	}
	.money-card__segment--items {
		background: var(--color-money--items);
	}
	.money-card__segment--expenses {
		background: var(--color-money--expenses);
	}
	.money-card__segment--labor {
		background: var(--color-money--labor);
	}
	.money-card__segment--profit {
		background: var(--color-money--profit);
	}
	.money-card__segment--loss {
		background: var(--color-money--loss);
	}
</style>
