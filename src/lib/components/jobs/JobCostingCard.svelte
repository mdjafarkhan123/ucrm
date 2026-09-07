<script lang="ts">
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import type { JobCosting } from '$lib/jobs/api';
	import coinIcon from '@tabler/icons/outline/coin.svg?raw';

	// What the job actually cost us set against what it sells for. Every figure here is one `job_costing`
	// worked out and sent back — this card formats money, it never adds it up. It only exists for a member
	// with jobs.view_cost; a page that was handed a null `costing` renders nothing.
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
		currencyCode = 'USD',
		locale = 'en-US'
	}: {
		costing: JobCosting | null;
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

{#if costing}
	<RailCard title="Job costing" icon={coinIcon}>
		<p class="job-costing__eyebrow">Only your team sees this</p>

		{#if recurring}
			<p class="job-costing__window">
				Last 30 days <span>{windowText}</span>
			</p>
		{/if}

		<dl class="job-costing">
			{#if recurring}
				<div class="job-costing__row">
					<dt>{recurring.unit_kind === 'visits' ? 'Visits' : 'Periods'}</dt>
					<dd>{unitText}</dd>
				</div>
			{/if}

			<!-- A dash, not a zero: manual billing sets no period, so nothing in the window says what the
			     work sold for. Zero would read as "we earned nothing", which is a different claim. -->
			<div class="job-costing__row">
				<dt>Revenue <span>before tax</span></dt>
				<dd>{costing.revenue_minor === null ? '—' : format(costing.revenue_minor)}</dd>
			</div>

			<div class="job-costing__group">
				<div class="job-costing__row">
					<dt>Item cost</dt>
					<dd>{format(costing.item_cost_minor)}</dd>
				</div>
				<div class="job-costing__row">
					<dt>Labor</dt>
					<dd>{format(costing.labor_cost_minor)}</dd>
				</div>
				<div class="job-costing__row">
					<dt>Expenses</dt>
					<dd>{format(costing.expense_cost_minor)}</dd>
				</div>
			</div>

			<div class="job-costing__row job-costing__row--sum">
				<dt>{open ? 'Costs so far' : 'Total cost'}</dt>
				<dd>{format(costing.total_cost_minor)}</dd>
			</div>

			<div class="job-costing__row job-costing__row--profit">
				<dt>{open ? 'Profit so far' : 'Profit'}</dt>
				<dd class:job-costing__loss={(costing.profit_minor ?? 0) < 0}>
					{costing.profit_minor === null ? '—' : format(costing.profit_minor)}
				</dd>
			</div>

			{#if !open}
				<div class="job-costing__row">
					<dt>Margin</dt>
					<dd>{marginText}</dd>
				</div>
			{/if}
		</dl>

		{#if recurring && recurring.revenue_minor === null}
			<p class="job-costing__note">
				This job is billed manually, so these 30 days have no billing period to price. The costs
				above are real; there is no revenue to set them against until the work is billed.
			</p>
		{/if}

		{#if costing.unrated_labor_count > 0}
			<p class="job-costing__note">
				{costing.unrated_labor_count === 1
					? 'One time entry has'
					: `${costing.unrated_labor_count} time entries have`}
				no hourly cost set, so those hours are not in the labor figure.
			</p>
		{/if}

		{#if costing.labor_line_and_time}
			<p class="job-costing__note job-costing__note--warn">
				This job has a labor line item and tracked time. Both are counted here — remove one if it is
				double counting.
			</p>
		{/if}
	</RailCard>
{/if}

<style lang="scss">
	.job-costing {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;

		&__row {
			display: flex;
			align-items: baseline;
			justify-content: space-between;
			gap: var(--space-base);

			dt {
				color: var(--color-text--secondary);

				span {
					font-size: var(--typography--fontSize-small);
				}
			}

			dd {
				margin: 0;
				color: var(--color-heading);
				font-weight: 600;
				font-variant-numeric: tabular-nums;
			}
		}

		/* Item, labor and expenses read as one indented group under revenue. */
		&__group {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding-left: var(--space-base);
		}

		/* The cost line the profit is drawn from, set off by a rule the way a printed statement does. */
		&__row--sum {
			padding-top: var(--space-small);
			border-top: var(--border-base) solid var(--color-border);

			dt {
				color: var(--color-heading);
				font-weight: 700;
			}
			dd {
				font-weight: 700;
			}
		}

		&__row--profit dt {
			color: var(--color-heading);
			font-weight: 700;
		}
		&__row--profit dd {
			font-weight: 700;
		}
	}

	.job-costing__loss {
		color: var(--color-critical);
	}

	.job-costing__eyebrow {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}

	/* The window the recurring figures below are measured over. The dates carry the weight, so they get the
	   heading colour and the label stays quiet. */
	.job-costing__window {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		span {
			color: var(--color-heading);
			font-weight: 600;
			font-variant-numeric: tabular-nums;
		}
	}

	.job-costing__note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		&--warn {
			color: var(--color-warning--onSurface);
		}
	}
</style>
