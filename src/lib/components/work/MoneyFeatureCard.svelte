<script module lang="ts">
	export type MoneyBreakdownPart = {
		label: string;
		/** The figure to show, already formatted. */
		value: string;
		/** How much of the whole bar this part fills; only the proportions between parts matter. */
		share: number;
		tone: 'critical' | 'neutral' | 'success' | 'muted';
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
	import type { Snippet } from 'svelte';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
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
		progress,
		change,
		badge,
		badgeIcon,
		pill,
		details,
		children,
		record = false,
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
		/** A thin bar over the plain rows, filled to this share (0 to 1). */
		progress?: number | null;
		/** A pill beside the big figure comparing it with the period before. */
		change?: { direction: 'up' | 'down' | 'same'; text: string } | null;
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
	class={['money-card', record && 'money-card--record']}
	aria-label={eyebrow}
	aria-busy={loading}
>
	{#if badge}
		<div class="money-card__top">
			<p class="money-card__eyebrow">{eyebrow}</p>
			<span class="money-card__badge">
				{#if badgeIcon}<span class="money-card__badge-icon" aria-hidden="true"
						>{@html badgeIcon}</span
					>{/if}
				{badge}
			</span>
		</div>
	{:else}
		<p class="money-card__eyebrow">{eyebrow}</p>
	{/if}
	<div class="money-card__figure">
		<div class="money-card__figure-row">
			<p class="money-card__value">{value}</p>
			{#if pill}
				<span class="money-card__pill">
					<span class="money-card__pill-icon" aria-hidden="true">{@html checkIcon}</span>
					{pill}
				</span>
			{/if}
			{#if change}
				<p class="money-card__change">
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
						<dd>
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
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

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
		&__change {
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
			padding-top: 14px;
			border-top: var(--border-base) solid
				color-mix(in srgb, var(--color-text--reverse) 8%, transparent);
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

			&--success {
				background: var(--color-success);
			}
			&--muted {
				background: var(--color-icon--secondary);
			}
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
		&__percent {
			margin-right: var(--space-small);
			color: var(--color-icon--secondary);
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
			background: color-mix(in srgb, var(--color-text--reverse) 8%, transparent);
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
			color: var(--color-icon--secondary);
		}
		&__pill {
			display: inline-flex;
			align-items: center;
			gap: 4px;
			margin-bottom: 2px;
			padding: 4px 9px;
			border-radius: 999px;
			color: var(--color-surface);
			background: var(--color-interactive);
			font-size: 13px;
			font-weight: 700;
		}
		&__foot {
			display: grid;
			gap: 12px;
			padding-top: 14px;
			border-top: var(--border-base) solid
				color-mix(in srgb, var(--color-text--reverse) 14%, transparent);
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
			background: color-mix(in srgb, var(--color-text--reverse) 8%, transparent);
			font-size: 13px;
			font-weight: 500;

			&:empty {
				display: none;
			}
		}
		// The record-page rail version: the split bar sits straight under the figure, with no hairline
		// above it, and the card's rows carry the hairline instead.
		&--record &__breakdown {
			padding-top: 0;
			border-top: 0;
		}
		&--record {
			gap: 20px;
			padding: 24px;
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
