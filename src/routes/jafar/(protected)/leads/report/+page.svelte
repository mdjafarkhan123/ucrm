<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { createQuery, keepPreviousData } from '@tanstack/svelte-query';
	import targetIcon from '@tabler/icons/outline/target.svg?raw';
	import shieldCheckIcon from '@tabler/icons/outline/shield-check.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import messageReplyIcon from '@tabler/icons/outline/message-reply.svg?raw';
	import phoneCallIcon from '@tabler/icons/outline/phone-call.svg?raw';
	import tagIcon from '@tabler/icons/outline/tag.svg?raw';
	import trophyIcon from '@tabler/icons/outline/trophy.svg?raw';
	import circleXIcon from '@tabler/icons/outline/circle-x.svg?raw';
	import chartBarIcon from '@tabler/icons/outline/chart-bar.svg?raw';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import FilterChip from '$lib/components/ui/FilterChip.svelte';
	import { LEAD_SOURCE_LABELS } from '$lib/jafar/leads';
	import { jafarActivityReportKey } from '$lib/jafar/query-keys';
	import {
		REPORT_PERIODS,
		REPORT_PERIOD_LABELS,
		REPORT_STEPS,
		fetchActivityReport,
		readReportPeriod,
		reportRange,
		reportRows,
		reportTotals,
		type ReportCount,
		type ReportPeriod
	} from '$lib/jafar/activity-report';

	// Jafar business management C3: what happened in a period, by where each business was found (plan § 6). A step
	// counts businesses once each; the second line under it counts the messages or calls behind them. The report
	// shows its last numbers straight away and refreshes every time it opens, so nothing else has to keep it fresh.

	const period = $derived(readReportPeriod(page.url.searchParams));
	let today = $state(new Date());
	$effect(() => {
		const refresh = () => {
			if (document.visibilityState === 'visible') today = new Date();
		};
		document.addEventListener('visibilitychange', refresh);
		return () => document.removeEventListener('visibilitychange', refresh);
	});
	const range = $derived(reportRange(period, today));

	const report = createQuery(() => ({
		queryKey: jafarActivityReportKey(range.from, range.to),
		queryFn: () => fetchActivityReport(range),
		staleTime: 0,
		placeholderData: keepPreviousData
	}));

	const rows = $derived(report.data ? reportRows(report.data.sources) : []);
	const totals = $derived(report.data ? reportTotals(report.data.sources) : null);

	const STEP_ICONS: Partial<Record<ReportCount, string>> = {
		researched: targetIcon,
		approved: shieldCheckIcon,
		reached: sendIcon,
		replied: messageReplyIcon,
		calls_held: phoneCallIcon,
		pricing_shared: tagIcon,
		won: trophyIcon,
		lost: circleXIcon
	};

	const STEP_NOTES: Partial<Record<ReportCount, string>> = {
		researched: 'Businesses researched and added',
		approved: 'Businesses cleared for first contact',
		pricing_shared: 'Businesses shown prices',
		lost: 'Deals lost'
	};

	const numbers = new Intl.NumberFormat('en-US');
	const dollars = new Intl.NumberFormat('en-US', {
		style: 'currency',
		currency: 'USD',
		maximumFractionDigits: 0
	});

	function stepNote(step: (typeof REPORT_STEPS)[number]) {
		if (!totals) return ' ';
		if (step.detail) return step.detail.words(totals[step.detail.key]);
		if (step.key === 'won')
			return totals.won_usd_cents > 0
				? `${dollars.format(totals.won_usd_cents / 100)} paid`
				: 'Deals won';
		return STEP_NOTES[step.key] ?? '';
	}

	// The second line in a table cell: the messages or calls behind the businesses counted.
	const CELL_DETAIL: Partial<Record<ReportCount, (count: number) => string>> = {
		reached: (n) => `${numbers.format(n)} sent`,
		replied: (n) => `${numbers.format(n)} received`,
		calls_held: (n) => `${numbers.format(n)} booked`
	};

	function showPeriod(next: string) {
		const params = new URLSearchParams(page.url.searchParams);
		if (next === 'this_month') params.delete('period');
		else params.set('period', next);
		const query = params.toString();
		// eslint-disable-next-line svelte/no-navigation-without-resolve -- the path comes from resolve(); only the query string is added.
		void goto(`${resolve('/jafar/leads/report')}${query ? `?${query}` : ''}`, {
			keepFocus: true,
			noScroll: true,
			replaceState: true
		});
	}

	const periodOptions = REPORT_PERIODS.map((value: ReportPeriod) => ({
		value,
		label: REPORT_PERIOD_LABELS[value]
	}));

	function dayLabel(iso: string) {
		const [year, month, day] = iso.split('-').map(Number);
		return new Date(year, month - 1, day).toLocaleDateString(undefined, {
			day: 'numeric',
			month: 'short',
			year: 'numeric'
		});
	}
	const rangeLabel = $derived(
		range.from ? `${dayLabel(range.from)} – ${dayLabel(range.to)}` : `Up to ${dayLabel(range.to)}`
	);
</script>

<svelte:head>
	<title>Activity report · Control Room</title>
</svelte:head>

<main class="report">
	<header class="report__header">
		<div>
			<p class="report__eyebrow">Business management</p>
			<h1>Activity report</h1>
			<p class="report__description">
				What happened with your Leads and Deals, and where those businesses were found.
			</p>
		</div>
		<div class="report__period">
			<FilterChip
				id="report-period"
				label="Period"
				value={period}
				options={periodOptions}
				onchange={showPeriod}
			/>
			<span class="report__range">{rangeLabel}</span>
		</div>
	</header>

	<section
		class="report__steps"
		class:report__steps--refreshing={report.isPlaceholderData}
		aria-label="Totals"
		aria-busy={report.isFetching}
	>
		{#each REPORT_STEPS as step (step.key)}
			<KpiCard
				label={step.label}
				value={totals ? numbers.format(totals[step.key]) : '–'}
				note={stepNote(step)}
				icon={STEP_ICONS[step.key] ?? chartBarIcon}
				tone={step.key === 'won' && totals && totals.won > 0 ? 'success' : 'default'}
				variant="compact"
			/>
		{/each}
	</section>

	<SectionBlock
		title="By where they were found"
		hint="Each business counts once per step. The smaller number shows the messages or calls behind them."
		variant="filled"
	>
		{#if report.isPending}
			<LoadingSkeleton variant="table" label="Loading the report" rows={4} />
		{:else if report.isError && !report.data}
			<ErrorState
				title="The report could not be loaded"
				description="Check your connection and try again."
				retry={() => report.refetch()}
			/>
		{:else if rows.length === 0}
			<EmptyState
				title="Nothing happened in this period"
				description="Leads added, contact logged, calls and Deals will be counted here."
				icon={chartBarIcon}
			/>
		{:else if totals}
			<div class="report__table-wrap" class:report__steps--refreshing={report.isPlaceholderData}>
				<table class="report__table">
					<thead>
						<tr>
							<th scope="col">Source</th>
							{#each REPORT_STEPS as step (step.key)}
								<th scope="col" class="report__number">{step.label}</th>
							{/each}
						</tr>
					</thead>
					<tbody>
						{#each rows as row (row.source)}
							<tr>
								<th scope="row">{LEAD_SOURCE_LABELS[row.source]}</th>
								{#each REPORT_STEPS as step (step.key)}
									<td class="report__number" class:report__number--zero={row[step.key] === 0}>
										{numbers.format(row[step.key])}
										{#if step.detail && CELL_DETAIL[step.key] && row[step.detail.key] > 0}
											<small>{CELL_DETAIL[step.key]?.(row[step.detail.key])}</small>
										{/if}
									</td>
								{/each}
							</tr>
						{/each}
					</tbody>
					{#if rows.length > 1}
						<tfoot>
							<tr>
								<th scope="row">All sources</th>
								{#each REPORT_STEPS as step (step.key)}
									<td class="report__number">
										{numbers.format(totals[step.key])}
										{#if step.detail && CELL_DETAIL[step.key] && totals[step.detail.key] > 0}
											<small>{CELL_DETAIL[step.key]?.(totals[step.detail.key])}</small>
										{/if}
									</td>
								{/each}
							</tr>
						</tfoot>
					{/if}
				</table>
			</div>
		{/if}
	</SectionBlock>

	<p class="report__footnote">
		A source is where a business was found. It shows what came from where, not that a particular
		message caused the sale.
		{#if report.data}Days follow your time zone, {report.data.time_zone.replaceAll('_', ' ')}.{/if}
	</p>
</main>

<style lang="scss">
	.report {
		min-width: 0;
		display: grid;
		gap: var(--space-large);
	}

	.report h1,
	.report p {
		margin: 0;
	}

	.report h1 {
		color: var(--color-heading);
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 900;
		line-height: var(--typography--lineHeight-minuscule);
	}

	.report__header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
		padding-bottom: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.report__eyebrow {
		margin-bottom: var(--space-small) !important;
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}

	.report__description {
		max-width: 65ch;
		margin-top: var(--space-small) !important;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
	}

	.report__period {
		display: grid;
		justify-items: end;
		gap: var(--space-smaller);
		flex-shrink: 0;
	}

	.report__range {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-variant-numeric: tabular-nums;
	}

	.report__steps {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-base);
	}

	// While another period is on its way, the numbers already shown stay and soften instead of vanishing.
	.report__steps--refreshing {
		opacity: 0.6;
		transition: opacity var(--timing-quick);
	}

	// Eight steps side by side; on a narrow screen the table scrolls sideways with the source kept in view.
	.report__table-wrap {
		overflow-x: auto;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		overscroll-behavior-x: contain;
	}

	.report__table {
		width: 100%;
		border-collapse: collapse;
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);

		th,
		td {
			padding: var(--space-base) var(--space-base);
			border-bottom: var(--border-base) solid var(--color-border);
			text-align: left;
			vertical-align: top;
		}

		thead th {
			padding-top: var(--space-slim);
			padding-bottom: var(--space-slim);
			background: var(--color-surface--background--subtle);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			white-space: nowrap;
		}

		tbody th,
		tfoot th {
			color: var(--color-heading);
			font-weight: 700;
			white-space: nowrap;
		}

		th:first-child {
			position: sticky;
			left: 0;
			z-index: 1;
			background: var(--color-surface);
			box-shadow: inset calc(-1 * var(--border-base)) 0 0 var(--color-border);
		}

		thead th:first-child {
			background: var(--color-surface--background--subtle);
		}

		tbody tr:last-child th,
		tbody tr:last-child td {
			border-bottom: 0;
		}

		tfoot th,
		tfoot td {
			border-top: var(--border-base) solid var(--color-border);
			border-bottom: 0;
			background: var(--color-surface--background--subtle);
			font-weight: 700;
		}

		tfoot th:first-child {
			background: var(--color-surface--background--subtle);
		}
	}

	.report__number {
		min-width: 96px;
		font-variant-numeric: tabular-nums;
		text-align: right !important;

		small {
			display: block;
			margin-top: 2px;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 400;
			white-space: nowrap;
		}
	}

	.report__number--zero {
		color: var(--color-text--secondary);
	}

	.report__footnote {
		max-width: 75ch;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-large);
	}

	@media (max-width: 1023px) {
		.report__steps {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	@media (max-width: 767px) {
		.report__header {
			flex-direction: column;
		}

		.report__period {
			justify-items: start;
		}
	}

	@media (max-width: 639px) {
		.report h1 {
			font-size: 28px;
		}
	}
</style>
