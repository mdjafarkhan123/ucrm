<script module lang="ts">
	export type PerformanceMetric = {
		key: string;
		label: string;
		/** A Tabler icon (raw SVG). */
		icon: string;
		tone: 'informative' | 'success';
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
	import HomeCardState from '$lib/components/dashboard/HomeCardState.svelte';
	import { formatWhole } from '$lib/home/format';
	import { percentChange } from '$lib/home/money';

	// Business performance: this month so far against last month up to the same day, one block per figure with
	// a change pill and two bars drawn to the same scale.
	let {
		metrics,
		currentLabel,
		previousLabel,
		currency = 'USD',
		locale = 'en-US',
		onretry
	}: {
		metrics: PerformanceMetric[];
		currentLabel: string;
		previousLabel: string;
		currency?: string;
		locale?: string;
		onretry?: (key: string) => void;
	} = $props();

	const money = (minor: number) => formatWhole(minor, currency, locale);
	const uid = $props.id();

	function width(metric: PerformanceMetric, value: number | null) {
		const biggest = Math.max(metric.current ?? 0, metric.previous ?? 0, 1);
		return `${Math.max(((value ?? 0) / biggest) * 100, value ? 3 : 0)}%`;
	}
	function change(metric: PerformanceMetric) {
		return metric.current === null || metric.previous === null
			? null
			: percentChange(metric.current, metric.previous);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="home-performance" aria-labelledby="{uid}-title">
	<header class="home-performance__header">
		<h2 id="{uid}-title">Business performance</h2>
		<p>Compared with the same days last month</p>
	</header>
	{#each metrics as metric (metric.key)}
		{@const delta = change(metric)}
		<div class="home-performance__metric">
			<p class="home-performance__label">
				<span class="home-performance__icon" aria-hidden="true">{@html metric.icon}</span>{metric.label}
			</p>
			{#if metric.loading}
				<HomeCardState state="loading" label={metric.label.toLowerCase()} rows={2} />
			{:else if metric.failed || metric.current === null}
				<HomeCardState
					state="error"
					label={metric.label.toLowerCase()}
					onretry={() => onretry?.(metric.key)}
				/>
			{:else}
				<div class="home-performance__value-row">
					<p class="home-performance__value">{money(metric.current)}</p>
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
				</div>
				<div class="home-performance__bars">
					{#each [{ label: currentLabel, value: metric.current, now: true }, { label: previousLabel, value: metric.previous, now: false }] as bar (bar.label)}
						<div class="home-performance__bar">
							<span class="home-performance__bar-label">{bar.label}</span>
							<span class="home-performance__track"
								><span
									class={[
										'home-performance__fill',
										bar.now && `home-performance__fill--${metric.tone}`
									]}
									style:width={width(metric, bar.value)}
								></span></span
							>
							<span class="home-performance__amount">{money(bar.value ?? 0)}</span>
						</div>
					{/each}
				</div>
			{/if}
		</div>
	{/each}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.home-performance {
		min-width: 0;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		&__header {
			display: grid;
			gap: 3px;
			padding: 20px 20px 16px;

			h2 {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
				font-weight: 700;
				letter-spacing: -0.2px;
			}
			p {
				color: var(--color-text--secondary);
				font-size: 12px;
				font-weight: 500;
			}
		}

		&__metric {
			display: grid;
			gap: 10px;
			padding: 16px 20px;
			border-top: var(--border-base) solid var(--color-border);
		}
		&__label {
			display: flex;
			align-items: center;
			gap: 8px;
			color: var(--color-text);
			font-size: 13px;
			font-weight: 600;
		}
		&__icon {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			width: 24px;
			height: 24px;
			border-radius: 7px;
			background: var(--color-surface--background--subtle);

			:global(svg) {
				width: 13px;
				height: 13px;
			}
		}
		&__value-row {
			display: flex;
			align-items: flex-end;
			justify-content: space-between;
			gap: var(--space-small);
		}
		&__value {
			color: var(--color-heading);
			font-size: 26px;
			font-weight: 800;
			letter-spacing: -0.8px;
			line-height: 1.15;
			font-variant-numeric: tabular-nums;
		}
		&__trend {
			display: inline-flex;
			align-items: center;
			gap: 3px;
			padding: 3px 8px 3px 6px;
			border-radius: 999px;
			color: var(--color-interactive);
			background: var(--color-success--surface);
			font-size: 12px;
			font-weight: 700;

			&--down {
				color: var(--color-critical);
				background: var(--color-critical--surface);
			}
			&--flat {
				padding-left: 8px;
				color: var(--color-text--secondary);
				background: var(--color-surface--background--subtle);
			}
		}
		&__trend-icon {
			display: inline-flex;

			:global(svg) {
				width: 13px;
				height: 13px;
			}
		}

		&__bars {
			display: grid;
			gap: 5px;
		}
		&__bar {
			display: flex;
			align-items: center;
			gap: 8px;
			color: var(--color-text--secondary);
			font-size: 11px;
			font-weight: 600;
		}
		&__bar-label {
			flex: 0 0 58px;
		}
		&__track {
			display: block;
			flex: 1;
			height: 6px;
			overflow: hidden;
			border-radius: 3px;
			background: var(--color-surface--background--subtle);
		}
		&__fill {
			display: block;
			height: 100%;
			border-radius: 3px;
			background: var(--color-icon--secondary);

			&--informative {
				background: var(--color-informative);
			}
			&--success {
				background: var(--color-success);
			}
		}
		&__amount {
			flex: 0 0 56px;
			text-align: right;
			font-variant-numeric: tabular-nums;
		}
	}
</style>
