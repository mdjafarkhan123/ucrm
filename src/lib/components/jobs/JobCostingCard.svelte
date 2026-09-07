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
	// cost, profit, and margin. A recurring job gets no figures from here — its profitability is measured over
	// a rolling period, which arrives in a later part.
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

	const open = $derived(costing?.costing_basis === 'one_off' && !costing.job_closed);
	const marginText = $derived(
		costing?.costing_basis === 'one_off' && costing.margin_basis_points !== null
			? `${(costing.margin_basis_points / 100).toFixed(1)}%`
			: '—'
	);
</script>

{#if costing}
	<RailCard title="Job costing" icon={coinIcon}>
		<p class="job-costing__eyebrow">Only your team sees this</p>

		{#if costing.costing_basis === 'recurring'}
			<p class="job-costing__note">
				Profit on a recurring job is measured over a rolling period. It will show here in a later
				update.
			</p>
		{:else}
			<dl class="job-costing">
				<div class="job-costing__row">
					<dt>Revenue <span>before tax</span></dt>
					<dd>{format(costing.revenue_minor)}</dd>
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
					<dd class:job-costing__loss={costing.profit_minor < 0}>
						{format(costing.profit_minor)}
					</dd>
				</div>

				{#if !open}
					<div class="job-costing__row">
						<dt>Margin</dt>
						<dd>{marginText}</dd>
					</div>
				{/if}
			</dl>

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
					This job has a labor line item and tracked time. Both are counted here — remove one if it
					is double counting.
				</p>
			{/if}
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

	.job-costing__note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		&--warn {
			color: var(--color-warning--onSurface);
		}
	}
</style>
