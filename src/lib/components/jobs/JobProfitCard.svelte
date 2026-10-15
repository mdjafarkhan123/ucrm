<script lang="ts">
	import type { JobCosting } from '$lib/jobs/api';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import trendIcon from '@tabler/icons/outline/trending-up.svg?raw';

	// The Classic job page's featured card (classic.pen "Profit card"): the same `job_costing` figures as
	// JobCostingCard, drawn as one headline profit, a split bar and its legend. It formats money and never
	// adds it up. The costing rules carry over unchanged: an open one-off job shows profit *so far* and no
	// margin, and a recurring job is measured over its stated last-30-days window.
	let {
		costing,
		currencyCode = 'USD',
		locale = 'en-US'
	}: {
		costing: JobCosting;
		currencyCode?: string;
		locale?: string;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat(locale, {
			style: 'currency',
			currency: currencyCode,
			maximumFractionDigits: 0
		})
	);
	const format = (minor: number) => money.format(minor / 100);

	const recurring = $derived(costing.costing_basis === 'one_off' ? null : costing);
	const open = $derived(costing.costing_basis === 'one_off' && !costing.job_closed);
	const eyebrow = $derived(open ? 'Profit so far' : 'Profit');
	const margin = $derived(
		!open && costing.margin_basis_points !== null
			? `${Math.round(costing.margin_basis_points / 100)}% margin`
			: null
	);
	const loss = $derived((costing.profit_minor ?? 0) < 0);

	// 'YYYY-MM-DD' is a calendar day; placing the parts by hand keeps it from slipping a day west of UTC.
	const asLocalDate = (text: string) => {
		const [year, month, day] = text.split('-').map(Number);
		return new Date(year, month - 1, day);
	};
	const dayMonth = $derived(new Intl.DateTimeFormat(locale, { month: 'short', day: 'numeric' }));

	const subline = $derived.by(() => {
		if (recurring) {
			const window = `${dayMonth.format(asLocalDate(recurring.window_start))} – ${dayMonth.format(
				asLocalDate(recurring.window_end)
			)}`;
			const units =
				recurring.unit_kind === 'visits'
					? `${recurring.unit_count} completed ${recurring.unit_count === 1 ? 'visit' : 'visits'}`
					: `${recurring.unit_count} billing ${recurring.unit_count === 1 ? 'period' : 'periods'}`;
			return `Last 30 days · ${window} · ${units}`;
		}
		return `On ${format(costing.revenue_minor ?? 0)} of work, before tax`;
	});

	// Each part's share of what the work sells for. When costs run past revenue the bar is measured against
	// the costs instead, so it still fills exactly once and profit simply has no segment.
	const parts = $derived.by(() => {
		const profit = Math.max(0, costing.profit_minor ?? 0);
		const base = Math.max(costing.revenue_minor ?? 0, costing.total_cost_minor + profit, 1);
		const rows = [
			{ key: 'items', label: 'Items', minor: costing.item_cost_minor },
			{ key: 'labor', label: 'Labor', minor: costing.labor_cost_minor },
			{ key: 'expenses', label: 'Expenses', minor: costing.expense_cost_minor },
			{ key: 'profit', label: 'Profit', minor: costing.profit_minor ?? 0 }
		].filter((row) => row.key !== 'items' || row.minor > 0);
		return rows.map((row) => ({
			...row,
			share: Math.max(0, row.minor) / base,
			percent: costing.revenue_minor ? Math.round((row.minor / costing.revenue_minor) * 100) : null
		}));
	});
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="profit-card" aria-label="Job profit">
	<header class="profit-card__header">
		<p class="profit-card__eyebrow">{eyebrow}</p>
		<span class="profit-card__team">
			<span aria-hidden="true">{@html lockIcon}</span>Team only
		</span>
	</header>

	<div class="profit-card__figure">
		<div class="profit-card__figure-row">
			<p class="profit-card__value" class:profit-card__value--loss={loss}>
				{costing.profit_minor === null ? '—' : format(costing.profit_minor)}
			</p>
			{#if margin}
				<span class="profit-card__margin">
					<span aria-hidden="true">{@html trendIcon}</span>{margin}
				</span>
			{/if}
		</div>
		<p class="profit-card__sub">{subline}</p>
	</div>

	{#if costing.revenue_minor !== null}
		<div class="profit-card__bar" aria-hidden="true">
			{#each parts as part (part.key)}
				{#if part.share > 0}
					<span
						class={`profit-card__segment profit-card__segment--${part.key}`}
						style:flex-grow={part.share}
					></span>
				{/if}
			{/each}
		</div>
	{/if}

	<dl class="profit-card__legend">
		{#each parts as part (part.key)}
			<div class="profit-card__row">
				<dt>
					<span class={`profit-card__swatch profit-card__segment--${part.key}`}></span>{part.label}
				</dt>
				<dd>
					{#if part.percent !== null}<span>{part.percent}%</span>{/if}
					<strong>{format(part.minor)}</strong>
				</dd>
			</div>
		{/each}
	</dl>

	{#if recurring && recurring.revenue_minor === null}
		<p class="profit-card__note">
			This job is billed manually, so these 30 days have no billing period to price. The costs above
			are real; there is no revenue to set them against until the work is billed.
		</p>
	{/if}
	{#if costing.unrated_labor_count > 0}
		<p class="profit-card__note">
			{costing.unrated_labor_count === 1
				? 'One time entry has'
				: `${costing.unrated_labor_count} time entries have`}
			no hourly cost set, so those hours are not in the labor figure.
		</p>
	{/if}
	{#if costing.labor_line_and_time}
		<p class="profit-card__note profit-card__note--warn">
			This job has a labor line item and tracked time. Both are counted here — remove one if it is
			double counting.
		</p>
	{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.profit-card {
		display: flex;
		flex-direction: column;
		gap: 20px;
		padding: 24px;
		border-radius: var(--classic2-radius-card);
		background: linear-gradient(
			120deg,
			var(--classic2-sidebar) 0%,
			var(--classic2-feature-mid) 60%,
			var(--classic2-feature-end) 100%
		);
		box-shadow: 0 10px 28px var(--classic2-shadow-feature);
		color: var(--classic2-white);
		font-family: var(--classic2-font);

		&__header {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: 12px;
		}

		&__eyebrow {
			margin: 0;
			color: var(--classic2-feature-eyebrow);
			font-size: var(--classic2-font-micro);
			font-weight: 700;
			letter-spacing: 1px;
			text-transform: uppercase;
		}

		&__team {
			display: inline-flex;
			align-items: center;
			gap: 5px;
			padding: 4px 9px;
			border-radius: 999px;
			background: var(--classic2-feature-chip);
			color: var(--classic2-feature-label);
			font-size: var(--classic2-font-small);
			font-weight: 600;

			span {
				display: inline-flex;
				color: var(--classic2-feature-eyebrow);
			}

			:global(svg) {
				width: 11px;
				height: 11px;
			}
		}

		&__figure {
			display: flex;
			flex-direction: column;
			gap: 6px;
		}

		&__figure-row {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: 10px;
		}

		&__value {
			margin: 0;
			color: var(--classic2-white);
			font-size: 40px;
			font-weight: 700;
			letter-spacing: -1.2px;
			line-height: 1;

			&--loss {
				color: var(--classic2-savebar-error);
			}
		}

		&__margin {
			display: inline-flex;
			align-items: center;
			gap: 4px;
			padding: 4px 9px;
			border-radius: 999px;
			background: var(--classic2-solid-green);
			color: var(--classic2-green-on);
			font-size: var(--classic2-font-label);
			font-weight: 700;

			span {
				display: inline-flex;
			}

			:global(svg) {
				width: 12px;
				height: 12px;
			}
		}

		&__sub {
			margin: 0;
			color: var(--classic2-feature-eyebrow);
			font-size: var(--classic2-font-label);
			font-weight: 500;
		}

		&__bar {
			display: flex;
			gap: 3px;
			height: 10px;
		}

		&__segment {
			flex-basis: 0;
			border-radius: 4px;

			&--items {
				background: var(--classic2-violet-dot);
			}

			&--labor {
				background: var(--classic2-blue-dot);
			}

			&--expenses {
				background: var(--classic2-amber-dot);
			}

			&--profit {
				background: var(--classic2-green-mid);
			}
		}

		&__legend {
			display: flex;
			flex-direction: column;
			gap: 10px;
			margin: 0;
		}

		&__row {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: 12px;
			font-size: var(--classic2-font-label);

			dt {
				display: inline-flex;
				align-items: center;
				gap: 8px;
				color: var(--classic2-feature-label);
				font-weight: 500;
			}

			dd {
				display: inline-flex;
				gap: 8px;
				margin: 0;

				span {
					color: var(--classic2-feature-muted);
					font-weight: 500;
				}

				strong {
					color: var(--classic2-white);
					font-weight: 600;
				}
			}
		}

		&__swatch {
			width: 8px;
			height: 8px;
			border-radius: 2px;
		}

		&__note {
			margin: 0;
			color: var(--classic2-feature-muted);
			font-size: var(--classic2-font-small);
			line-height: 1.45;

			&--warn {
				color: var(--classic2-amber-dot);
			}
		}
	}
</style>
