<script lang="ts">
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import { formatMoney } from '$lib/pipeline/money';
	import type { OutcomesReport, OutcomesReportGroup } from '$lib/pipeline/api';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import circleXIcon from '@tabler/icons/outline/circle-x.svg?raw';
	import briefcaseIcon from '@tabler/icons/outline/briefcase.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';

	// The headline numbers above the Sales Outcomes list, for the same date window. Won, Lost and Direct
	// jobs are three separate figures: a Direct job is booked work that never was a deal on the board.
	let { report }: { report: OutcomesReport } = $props();

	function days(value: number) {
		return `${value} ${value === 1 ? 'day' : 'days'}`;
	}

	// "$12,000 · 2 unvalued". A group with nothing valued reads "Unvalued", never $0, and a member who may
	// not see money gets only the unvalued count if it is relevant at all.
	function groupNote(group: OutcomesReportGroup) {
		if (group.count === 0) return 'None in this period';
		const parts: string[] = [];
		if (report.can_view_value) {
			const total = group.value_total;
			if (total !== null && total !== undefined) parts.push(formatMoney(total, report) ?? '');
		}
		if (group.unvalued_count > 0) {
			parts.push(
				group.unvalued_count === group.count ? 'Unvalued' : `${group.unvalued_count} unvalued`
			);
		}
		return parts.filter(Boolean).join(' · ') || 'Closed in this period';
	}

	const daysToWin = $derived(report.days_to_win);
	const lostTotal = $derived(report.lost.count);
</script>

<section class="outcomes-summary" aria-label="Sales Outcomes summary">
	<div class="outcomes-summary__tiles">
		<KpiCard
			variant="compact"
			tone="success"
			label="Won"
			value={String(report.won.count)}
			note={groupNote(report.won)}
			icon={circleCheckIcon}
		/>
		<KpiCard
			variant="compact"
			tone="critical"
			label="Lost"
			value={String(report.lost.count)}
			note={groupNote(report.lost)}
			icon={circleXIcon}
		/>
		<KpiCard
			variant="compact"
			tone="informative"
			label="Direct jobs"
			value={String(report.direct_job.count)}
			note={report.direct_job.count === 0
				? 'None in this period'
				: `Counted apart from Won · ${groupNote(report.direct_job)}`}
			icon={briefcaseIcon}
		/>
		<KpiCard
			variant="compact"
			label="Days to win"
			value={daysToWin.median === null ? '—' : days(daysToWin.median)}
			note={daysToWin.median === null || daysToWin.average === null
				? 'Nothing won in this period'
				: `Median · average ${days(daysToWin.average)}`}
			icon={clockIcon}
		/>
	</div>

	{#if lostTotal > 0}
		<div class="outcomes-summary__reasons">
			<h2 class="outcomes-summary__heading">Why deals were lost</h2>
			<ul class="outcomes-summary__list">
				{#each report.lost_reasons as line (line.reason ?? 'none')}
					{@const share = Math.round((line.count / lostTotal) * 100)}
					<li class="outcomes-summary__reason">
						<span class="outcomes-summary__reason-label">{line.label}</span>
						<span class="outcomes-summary__reason-count">
							{line.count}
							<small>{share}%</small>
						</span>
						<span class="outcomes-summary__bar" aria-hidden="true">
							<span class="outcomes-summary__bar-fill" style:width={`${share}%`}></span>
						</span>
					</li>
				{/each}
			</ul>
		</div>
	{/if}
</section>

<style lang="scss">
	.outcomes-summary {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		margin-bottom: var(--space-base);
	}
	.outcomes-summary__tiles {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-small);

		@media (max-width: 1023px) {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		@media (max-width: 479px) {
			grid-template-columns: minmax(0, 1fr);
		}
	}
	.outcomes-summary__reasons {
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}
	.outcomes-summary__heading {
		margin: 0 0 var(--space-small);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
	}
	.outcomes-summary__list {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	// Name and count on one line, the share bar underneath: readable at phone width without a table.
	.outcomes-summary__reason {
		display: grid;
		grid-template-columns: minmax(0, 1fr) auto;
		gap: var(--space-smaller) var(--space-small);
		align-items: baseline;
	}
	.outcomes-summary__reason-label {
		min-width: 0;
		color: var(--color-text);
		overflow-wrap: anywhere;
	}
	.outcomes-summary__reason-count {
		color: var(--color-heading);
		font-weight: 600;
		font-variant-numeric: tabular-nums;

		small {
			margin-left: 6px;
			color: var(--color-text--secondary);
			font-weight: 400;
		}
	}
	.outcomes-summary__bar {
		grid-column: 1 / -1;
		height: 6px;
		// A fixed radius: the circle token is a percentage, which tapers a bar this thin.
		border-radius: 3px;
		background: var(--color-inactive--surface);
		overflow: hidden;
	}
	.outcomes-summary__bar-fill {
		display: block;
		height: 100%;
		border-radius: inherit;
		background: var(--color-critical);
	}
</style>
