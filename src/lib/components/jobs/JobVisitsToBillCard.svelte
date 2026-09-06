<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { SvelteSet } from 'svelte/reactivity';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import type { JobVisit } from '$lib/jobs/api';

	// Manual per-visit billing (Invoices 5b-2): for a job priced per visit, this is the picker itself, not a
	// dialog reached from a menu — the job's page already knows which of its own visits are completed and
	// unbilled, so there is nothing to fetch. Ticking visits and pressing Create invoice hands the choice
	// straight to /invoices/new, which seeds one copy of the job's priced lines per visit, each dated to it.
	let {
		jobId,
		clientId,
		visits,
		subtotalMinor,
		currencyCode = 'USD',
		locale = 'en-US'
	}: {
		jobId: string;
		clientId: string;
		visits: JobVisit[];
		/** The job's own subtotal — what one visit's copy of the lines comes to. Null without price access. */
		subtotalMinor: number | null;
		currencyCode?: string;
		locale?: string;
	} = $props();

	const billable = $derived(
		visits.filter((visit) => visit.completed_at !== null && !visit.invoiced)
	);

	const selected = new SvelteSet<string>();

	function toggle(visitId: string) {
		if (selected.has(visitId)) selected.delete(visitId);
		else selected.add(visitId);
	}

	const dateFormat = $derived(
		new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric' })
	);
	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	function amount(minor: number) {
		return money.format(minor / 100);
	}

	const selectedTotal = $derived(subtotalMinor !== null ? subtotalMinor * selected.size : null);

	function createInvoice() {
		if (selected.size === 0) return;
		const visitIds = [...selected].join(',');
		void goto(
			`${resolve('/(app)/invoices/new')}?client=${clientId}&job=${jobId}&visits=${visitIds}`
		);
	}
</script>

{#if billable.length > 0}
	<RailCard title="Visits ready to bill" count={billable.length}>
		<ul class="visits-to-bill">
			{#each billable as visit (visit.id)}
				<li class="visits-to-bill__item">
					<Checkbox
						id={`visit-to-bill-${visit.id}`}
						checked={selected.has(visit.id)}
						onchange={() => toggle(visit.id)}
						label={visit.visit_date
							? `Bill the visit completed ${dateFormat.format(new Date(`${visit.visit_date}T12:00:00`))}`
							: 'Bill this visit'}
						hideLabel
					/>
					<span class="visits-to-bill__date">
						{visit.visit_date
							? dateFormat.format(new Date(`${visit.visit_date}T12:00:00`))
							: 'No visit date'}
					</span>
					{#if subtotalMinor !== null}
						<span class="visits-to-bill__amount">{amount(subtotalMinor)}</span>
					{/if}
				</li>
			{/each}
		</ul>

		<footer class="visits-to-bill__footer">
			{#if selectedTotal !== null}
				<span class="visits-to-bill__total">{selected.size} selected · {amount(selectedTotal)}</span
				>
			{:else}
				<span class="visits-to-bill__total">{selected.size} selected</span>
			{/if}
			<Button variant="primary" size="small" disabled={selected.size === 0} onclick={createInvoice}>
				Create invoice
			</Button>
		</footer>
	</RailCard>
{/if}

<style lang="scss">
	.visits-to-bill {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;

		&__item {
			display: flex;
			align-items: center;
			gap: var(--space-small);

			& + & {
				border-top: var(--border-base) solid var(--color-border);
				padding-top: var(--space-base);
			}
		}

		&__date {
			flex: 1;
			min-width: 0;
			color: var(--color-heading);
		}

		&__amount {
			color: var(--color-text--secondary);
			font-variant-numeric: tabular-nums;
			white-space: nowrap;
		}
	}

	.visits-to-bill__footer {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		padding-top: var(--space-small);
		border-top: var(--border-base) solid var(--color-border);
	}

	.visits-to-bill__total {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
</style>
