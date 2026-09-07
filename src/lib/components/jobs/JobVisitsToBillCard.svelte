<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { createQuery } from '@tanstack/svelte-query';
	import { SvelteSet } from 'svelte/reactivity';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import { fetchJobVisitLines, jobVisitLinesKey, type JobVisit } from '$lib/jobs/api';

	// Manual per-visit billing (Invoices 5b-2): for a job priced per visit, this is the picker itself, not a
	// dialog reached from a menu — the job's page already knows which of its own visits are completed and
	// unbilled. Ticking visits and pressing Create invoice hands the choice straight to /invoices/new, which
	// seeds each visit's own effective lines, dated to it.
	let {
		jobId,
		clientId,
		visits,
		canSeePrice = true,
		currencyCode = 'USD',
		locale = 'en-US'
	}: {
		jobId: string;
		clientId: string;
		visits: JobVisit[];
		/** Money is withheld from a member without jobs.view_price, so the card shows dates only. */
		canSeePrice?: boolean;
		currencyCode?: string;
		locale?: string;
	} = $props();

	const billable = $derived(
		visits.filter((visit) => visit.completed_at !== null && !visit.invoiced)
	);

	// Since 5c-5a a visit can carry its own quantities, so each row is worth what THAT visit bills, not one
	// copy of the job's lines. `job_visit_lines` answers for all of them in one gated read — it hands back the
	// job's lines for any visit that was never customised — and caps at 100 visits, which the slice respects.
	const pricedIds = $derived(billable.slice(0, 100).map((visit) => visit.id));
	const subtotalsQuery = createQuery(() => ({
		queryKey: jobVisitLinesKey(jobId, pricedIds),
		queryFn: () => fetchJobVisitLines(jobId, pricedIds),
		enabled: canSeePrice && pricedIds.length > 0,
		staleTime: 60 * 1000
	}));
	const subtotalByVisitId = $derived(
		new Map((subtotalsQuery.data ?? []).map((visit) => [visit.visit_id, visit.subtotal_minor]))
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

	// Only a total we can stand behind: if any ticked visit's own subtotal has not arrived, no figure shows.
	const selectedTotal = $derived.by(() => {
		let total = 0;
		for (const visitId of selected) {
			const subtotal = subtotalByVisitId.get(visitId);
			if (subtotal === undefined || subtotal === null) return null;
			total += subtotal;
		}
		return total;
	});

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
					{#if subtotalByVisitId.get(visit.id) != null}
						<span class="visits-to-bill__amount">{amount(subtotalByVisitId.get(visit.id)!)}</span>
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
