<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { SvelteSet } from 'svelte/reactivity';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import type { JobInvoiceReminder } from '$lib/jobs/api';

	// Manual period billing (Invoices 5b-3): for a job priced per period, this is the picker itself, not a
	// dialog reached from a menu — the job's page already knows which of its own reminders are due, so there
	// is nothing to fetch. Ticking periods and pressing Create invoice hands the choice straight to
	// /invoices/new, which seeds one copy of the job's priced lines per period, each dated to its end.
	let {
		jobId,
		clientId,
		reminders,
		today,
		subtotalMinor,
		currencyCode = 'USD',
		locale = 'en-US'
	}: {
		jobId: string;
		clientId: string;
		reminders: JobInvoiceReminder[];
		today: string;
		/** The job's own subtotal — what one period's copy of the lines comes to. Null without price access. */
		subtotalMinor: number | null;
		currencyCode?: string;
		locale?: string;
	} = $props();

	// Only the two calendar reminder kinds bound a period; on_completion/per_visit reminders aren't period
	// boundaries. "Due" uses the same string-compare the reminders card and the derived job status both use.
	const billable = $derived(
		reminders.filter(
			(reminder) =>
				(reminder.reminder_kind === 'monthly_last_day' ||
					reminder.reminder_kind === 'custom_date') &&
				reminder.due_on <= today
		)
	);

	const selected = new SvelteSet<string>();

	function toggle(reminderId: string) {
		if (selected.has(reminderId)) selected.delete(reminderId);
		else selected.add(reminderId);
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
		const reminderIds = [...selected].join(',');
		void goto(
			`${resolve('/(app)/invoices/new')}?client=${clientId}&job=${jobId}&reminders=${reminderIds}`
		);
	}
</script>

{#if billable.length > 0}
	<RailCard title="Periods ready to bill" count={billable.length}>
		<ul class="periods-to-bill">
			{#each billable as reminder (reminder.id)}
				<li class="periods-to-bill__item">
					<Checkbox
						id={`period-to-bill-${reminder.id}`}
						checked={selected.has(reminder.id)}
						onchange={() => toggle(reminder.id)}
						label={`Bill the period ending ${dateFormat.format(new Date(`${reminder.due_on}T12:00:00`))}`}
						hideLabel
					/>
					<span class="periods-to-bill__date">
						Period ending {dateFormat.format(new Date(`${reminder.due_on}T12:00:00`))}
					</span>
					{#if subtotalMinor !== null}
						<span class="periods-to-bill__amount">{amount(subtotalMinor)}</span>
					{/if}
				</li>
			{/each}
		</ul>

		<footer class="periods-to-bill__footer">
			{#if selectedTotal !== null}
				<span class="periods-to-bill__total"
					>{selected.size} selected · {amount(selectedTotal)}</span
				>
			{:else}
				<span class="periods-to-bill__total">{selected.size} selected</span>
			{/if}
			<Button variant="primary" size="small" disabled={selected.size === 0} onclick={createInvoice}>
				Create invoice
			</Button>
		</footer>
	</RailCard>
{/if}

<style lang="scss">
	.periods-to-bill {
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

	.periods-to-bill__footer {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		padding-top: var(--space-small);
		border-top: var(--border-base) solid var(--color-border);
	}

	.periods-to-bill__total {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
</style>
