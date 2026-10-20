<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import cashIcon from '@tabler/icons/outline/cash.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import type { JobCosting } from '$lib/jobs/api';

	// The Job total card (concept `tNdkX`) combines the saved selling total with the permission-gated costing
	// breakdown. Every figure is returned by the server; this card only formats money.
	//
	// While a one-off job is open the numbers are costs *so far*: a running tally, not a settled result, so
	// there is a "Profit so far" but no margin percentage. Once the job closes the same rows become the final
	// cost, profit, and margin.
	//
	// A recurring agreement has no end to total up against, so it is measured over the last 30 days instead.
	// That window is always complete on its own terms, so it always carries a margin — and the exact dates are
	// named on screen, because "last 30 days" alone is a figure nobody can check.
	let {
		costing,
		subtotalMinor,
		taxMinor = 0,
		totalMinor = null,
		currencyCode = 'USD',
		locale = 'en-US'
	}: {
		costing: JobCosting | null;
		subtotalMinor: number | null;
		taxMinor?: number;
		totalMinor?: number | null;
		currencyCode?: string;
		locale?: string;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	const format = (minor: number) => money.format(minor / 100);

	const recurring = $derived(
		costing?.costing_basis === 'per_visit' || costing?.costing_basis === 'fixed_per_period'
			? costing
			: null
	);

	const open = $derived(costing?.costing_basis === 'one_off' && !costing.job_closed);
	const marginText = $derived(
		costing && costing.margin_basis_points !== null
			? `${(costing.margin_basis_points / 100).toFixed(1)}%`
			: '—'
	);
	const barTotal = $derived(
		costing ? Math.max(costing.total_cost_minor, costing.revenue_minor ?? 0, 1) : 1
	);
	const barProfit = $derived(Math.max(costing?.profit_minor ?? 0, 0));

	const grandTotal = $derived(subtotalMinor === null ? null : (totalMinor ?? subtotalMinor));
	const beforeTax = $derived(grandTotal === null ? null : grandTotal - taxMinor);

	// A 'YYYY-MM-DD' from Postgres is a calendar day, not an instant. `new Date(text)` would read it as UTC
	// midnight and render the day before for anyone west of Greenwich, so the parts are placed by hand.
	const asLocalDate = (text: string) => {
		const [year, month, day] = text.split('-').map(Number);
		return new Date(year, month - 1, day);
	};
	const dayMonth = $derived(new Intl.DateTimeFormat(locale, { month: 'short', day: 'numeric' }));
	const dayMonthYear = $derived(
		new Intl.DateTimeFormat(locale, { month: 'short', day: 'numeric', year: 'numeric' })
	);
	const windowText = $derived(
		recurring
			? `${dayMonth.format(asLocalDate(recurring.window_start))} – ${dayMonthYear.format(
					asLocalDate(recurring.window_end)
				)}`
			: ''
	);

	// What the window's revenue was earned per. Zero units is the honest empty state, not an error.
	const unitText = $derived.by(() => {
		if (!recurring) return '';
		const { unit_count, unit_kind } = recurring;
		if (unit_kind === 'visits') {
			return unit_count === 1 ? '1 completed visit' : `${unit_count} completed visits`;
		}
		return unit_count === 1 ? '1 billing period' : `${unit_count} billing periods`;
	});
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if costing || subtotalMinor !== null}
	<section class="job-total" aria-label="Job total">
		<header class="job-total__head">
			<IconTile icon={cashIcon} tone="feature" size={40} />
			<h2 class="job-total__title">Job total</h2>
			{#if costing}
				<span class="job-total__team"><span aria-hidden="true">{@html lockIcon}</span>Team only</span>
			{/if}
		</header>

		{#if grandTotal === null}
			<p class="job-total__note">You do not have access to job prices.</p>
		{:else}
			<div class="job-total__sum">
				<p class="job-total__amount">{format(grandTotal)}</p>
				{#if beforeTax !== null && taxMinor > 0}
					<p class="job-total__sub">{format(beforeTax)} before tax</p>
				{/if}
			</div>
		{/if}

		{#if costing}
			<div class="job-total__panel">
				{#if recurring}
					<p class="job-total__window">
						Last 30 days <span>{windowText}</span> · {unitText}
					</p>
				{/if}

				<div class="job-total__figures">
					<div>
						<p class="job-total__label">{open ? 'Profit so far' : 'Profit'}</p>
						<p class="job-total__figure" class:job-total__loss={(costing.profit_minor ?? 0) < 0}>
							{costing.profit_minor === null ? '—' : format(costing.profit_minor)}
						</p>
					</div>
					<div class="job-total__figures-end">
						<p class="job-total__label">{open ? 'Costs so far' : 'Total cost'}</p>
						<p class="job-total__figure job-total__figure--small">
							{format(costing.total_cost_minor)}
						</p>
					</div>
				</div>

				<div
					class="job-total__bar"
					role="img"
					aria-label={`Item cost ${format(costing.item_cost_minor)}, labor ${format(costing.labor_cost_minor)}, expenses ${format(costing.expense_cost_minor)}, ${open ? 'profit so far' : 'profit'} ${costing.profit_minor === null ? 'not available' : format(costing.profit_minor)}`}
				>
					<span
						class="job-total__bar-items"
						style:width={`${(costing.item_cost_minor / barTotal) * 100}%`}
					></span>
					<span
						class="job-total__bar-labor"
						style:width={`${(costing.labor_cost_minor / barTotal) * 100}%`}
					></span>
					<span
						class="job-total__bar-expenses"
						style:width={`${(costing.expense_cost_minor / barTotal) * 100}%`}
					></span>
					<span class="job-total__bar-profit" style:width={`${(barProfit / barTotal) * 100}%`}
					></span>
				</div>

				<dl class="job-total__legend">
					<div class="job-total__legend-row">
						<span class="job-total__dot job-total__bar-items" aria-hidden="true"></span>
						<dt>Item cost</dt>
						<dd>{format(costing.item_cost_minor)}</dd>
					</div>
					<div class="job-total__legend-row">
						<span class="job-total__dot job-total__bar-labor" aria-hidden="true"></span>
						<dt>Labor</dt>
						<dd>{format(costing.labor_cost_minor)}</dd>
					</div>
					<div class="job-total__legend-row">
						<span class="job-total__dot job-total__bar-expenses" aria-hidden="true"></span>
						<dt>Expenses</dt>
						<dd>{format(costing.expense_cost_minor)}</dd>
					</div>
					<div class="job-total__legend-row">
						<span class="job-total__dot job-total__bar-profit" aria-hidden="true"></span>
						<dt>{open ? 'Profit so far' : 'Profit'}</dt>
						<dd>{costing.profit_minor === null ? '—' : format(costing.profit_minor)}</dd>
					</div>
				</dl>
			</div>

			<p class="job-total__note">
				{#if open}
					Margin shows once the job is closed.
				{:else}
					Margin {marginText}
				{/if}
			</p>

			{#if recurring && recurring.revenue_minor === null}
				<p class="job-total__note">
					This job is billed manually, so these 30 days have no billing period to price. The costs
					above are real; there is no revenue to set them against until the work is billed.
				</p>
			{/if}

			{#if costing.unrated_labor_count > 0}
				<p class="job-total__note">
					{costing.unrated_labor_count === 1
						? 'One time entry has'
						: `${costing.unrated_labor_count} time entries have`}
					no hourly cost set, so those hours are not in the labor figure.
				</p>
			{/if}

			{#if costing.labor_line_and_time}
				<p class="job-total__note job-total__note--warn">
					This job has a labor line item and tracked time. Both are counted here — remove one if it
					is double counting.
				</p>
			{/if}
		{/if}
	</section>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// The dark green card at the head of the rail. Its colours come from the `--color-feature--*` tokens,
	// so it reads the same in light and dark mode.
	.job-total {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		padding: var(--space-large);
		border-radius: var(--radius-large);
		color: var(--color-feature--text);
		background: linear-gradient(135deg, var(--color-feature--start), var(--color-feature--end));

		&__head {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
		}

		&__title {
			flex: 1;
			margin: 0;
			color: var(--color-feature--text--secondary);
			font-size: var(--typography--fontSize-overline);
			font-weight: 600;
			letter-spacing: 0.08em;
			text-transform: uppercase;
		}

		&__team {
			display: inline-flex;
			align-items: center;
			gap: 4px;
			padding: 3px 10px 3px 8px;
			border: var(--border-base) solid var(--color-feature--border);
			border-radius: var(--radius-circle);
			color: var(--color-feature--text--secondary);
			background: var(--color-feature--subtle);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;

			:global(svg) {
				display: block;
				width: 12px;
				height: 12px;
			}
		}

		&__sum {
			display: flex;
			flex-direction: column;
			gap: 2px;
		}

		&__amount {
			margin: 0;
			font-size: 34px;
			font-weight: 700;
			font-variant-numeric: tabular-nums;
			letter-spacing: -0.8px;
			line-height: 1.1;
		}

		&__sub {
			margin: 0;
			color: var(--color-feature--text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__panel {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-feature--border);
			border-radius: var(--radius-base);
			background: var(--color-feature--subtle);
		}

		&__window {
			margin: 0;
			color: var(--color-feature--text--secondary);
			font-size: var(--typography--fontSize-small);

			span {
				color: var(--color-feature--text);
				font-weight: 600;
				font-variant-numeric: tabular-nums;
			}
		}

		&__figures {
			display: flex;
			align-items: flex-end;
			justify-content: space-between;
			gap: var(--space-base);
		}

		&__figures-end {
			text-align: right;
		}

		&__label {
			margin: 0;
			color: var(--color-feature--text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__figure {
			margin: 0;
			font-size: var(--typography--fontSize-largest);
			font-weight: 700;
			font-variant-numeric: tabular-nums;

			&--small {
				font-size: var(--typography--fontSize-larger);
			}
		}

		&__loss {
			color: var(--color-feature--alert);
		}

		&__bar {
			display: flex;
			gap: 3px;
			width: 100%;
			height: 10px;
			overflow: hidden;
			border-radius: var(--radius-circle);
			background: var(--color-feature--subtle);

			span {
				display: block;
				height: 100%;
			}
		}

		&__bar-items {
			background: var(--color-feature--items);
		}
		&__bar-labor {
			background: var(--color-feature--labor);
		}
		&__bar-expenses {
			background: var(--color-feature--expenses);
		}
		&__bar-profit {
			background: var(--color-feature--text);
		}

		&__legend {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
		}

		&__legend-row {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			font-size: var(--typography--fontSize-small);

			dt {
				flex: 1;
				color: var(--color-feature--text--secondary);
			}

			dd {
				margin: 0;
				font-weight: 600;
				font-variant-numeric: tabular-nums;
			}
		}

		&__dot {
			flex: 0 0 auto;
			width: 10px;
			height: 10px;
			border-radius: var(--radius-circle);
		}

		&__note {
			margin: 0;
			color: var(--color-feature--text--secondary);
			font-size: var(--typography--fontSize-small);

			&--warn {
				color: var(--color-feature--text);
			}
		}
	}
</style>
