<script module lang="ts">
	export type PerformanceMetric = {
		key: string;
		label: string;
		/** Minor units; null while loading or when the read failed. */
		current: number | null;
		previous: number | null;
		loading: boolean;
		failed: boolean;
	};
</script>

<script lang="ts">
	import arrowDownRightIcon from '@tabler/icons/outline/arrow-down-right.svg?raw';
	import arrowUpRightIcon from '@tabler/icons/outline/arrow-up-right.svg?raw';
	import trendingUpIcon from '@tabler/icons/outline/trending-up.svg?raw';
	import HomeCardState from '$lib/components/dashboard/HomeCardState.svelte';
	import CardHeader from '$lib/components/ui/CardHeader.svelte';
	import { formatWhole } from '$lib/home/format';
	import { percentChange } from '$lib/home/money';

	// Business performance: this month so far against last month up to the same day, one row per figure with
	// a change pill and the period it is compared with.
	let {
		metrics,
		previousLabel,
		currency = 'USD',
		locale = 'en-US',
		onretry
	}: {
		metrics: PerformanceMetric[];
		/** The period each figure is compared with, e.g. "Sep 1–18". */
		previousLabel: string;
		currency?: string;
		locale?: string;
		onretry?: (key: string) => void;
	} = $props();

	const money = (minor: number) => formatWhole(minor, currency, locale);
	const uid = $props.id();

	function change(metric: PerformanceMetric) {
		return metric.current === null || metric.previous === null
			? null
			: percentChange(metric.current, metric.previous);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="home-performance" aria-labelledby="{uid}-title">
	<CardHeader id="{uid}-title" title="Business performance" icon={trendingUpIcon} tone="growth" />
	<div class="home-performance__body">
		{#each metrics as metric (metric.key)}
			{@const delta = change(metric)}
			<div class="home-performance__metric">
				{#if metric.loading}
					<p class="home-performance__label">{metric.label}</p>
					<HomeCardState state="loading" label={metric.label.toLowerCase()} rows={1} />
				{:else if metric.failed || metric.current === null}
					<p class="home-performance__label">{metric.label}</p>
					<HomeCardState
						state="error"
						label={metric.label.toLowerCase()}
						onretry={() => onretry?.(metric.key)}
					/>
				{:else}
					<div class="home-performance__row">
						<div class="home-performance__text">
							<p class="home-performance__label">{metric.label}</p>
							<p class="home-performance__value">{money(metric.current)}</p>
						</div>
						<div class="home-performance__change">
							{#if delta !== null}
								<span
									class={[
										'home-performance__trend',
										delta < 0 && 'home-performance__trend--down',
										delta === 0 && 'home-performance__trend--flat'
									]}
									aria-label={delta === 0
										? 'No change from last month'
										: `${Math.abs(delta)} percent ${delta > 0 ? 'up' : 'down'} from last month`}
								>
									{#if delta !== 0}<span class="home-performance__trend-icon" aria-hidden="true"
											>{@html delta > 0 ? arrowUpRightIcon : arrowDownRightIcon}</span
										>{/if}{delta === 0 ? 'Same' : `${Math.abs(delta)}%`}
								</span>
							{/if}
							<span
								class="home-performance__compared"
								title="{previousLabel}: {money(metric.previous ?? 0)}">vs {previousLabel}</span
							>
						</div>
					</div>
				{/if}
			</div>
		{/each}
	</div>
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.home-performance {
		min-width: 0;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__body {
			display: grid;
			gap: var(--space-slim);
			padding: var(--space-medium);
		}
		&__metric {
			display: grid;
			gap: 2px;

			& + & {
				padding-top: var(--space-slim);
				border-top: var(--border-base) solid var(--color-border);
			}
			:global(.home-state--loading),
			:global(.home-state--message) {
				padding: var(--space-small) 0;
			}
		}
		&__row {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: 10px 0;
		}
		&__text {
			display: grid;
			min-width: 0;
			flex: 1;
			gap: 2px;
		}
		&__label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-label);
			font-weight: 500;
		}
		&__value {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
			font-weight: 700;
			font-variant-numeric: tabular-nums;
		}
		&__change {
			display: grid;
			flex: 0 0 auto;
			justify-items: end;
			gap: 2px;
		}
		&__trend {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			height: 22px;
			padding: 0 var(--space-small);
			border-radius: var(--radius-circle);
			color: var(--color-success--onSurface);
			background: var(--color-success--surface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			font-variant-numeric: tabular-nums;

			&--down {
				color: var(--color-warning--onSurface);
				background: var(--color-warning--surface);
			}
			&--flat {
				color: var(--color-inactive--onSurface);
				background: var(--color-inactive--surface);
			}
		}
		&__trend-icon {
			display: inline-flex;

			:global(svg) {
				width: 12px;
				height: 12px;
			}
		}
		&__compared {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
