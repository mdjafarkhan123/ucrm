<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import {
		billableWorkKey,
		fetchBillableWork,
		type BillableWorkItem
	} from '$lib/invoices/api';
	import {
		JOB_STATUS_LABELS,
		JOB_STATUS_TONES,
		type JobDerivedStatus
	} from '$lib/jobs/statuses';

	// "Select work to invoice" — the step between pressing Create invoice on a job and filling the form.
	//
	// It lists every job of this client that no invoice has claimed yet, not only the one the contractor came
	// from, because one bill may cover several of a client's jobs. The job they came from arrives pre-ticked.
	// Choosing here decides what the invoice claims; the form after it decides what the invoice says.
	let {
		open,
		clientId,
		clientName,
		initialJobId = null,
		currencyCode = 'USD',
		locale = 'en-US',
		onCancel,
		onContinue
	}: {
		open: boolean;
		clientId: string;
		clientName: string;
		initialJobId?: string | null;
		currencyCode?: string;
		locale?: string;
		onCancel: () => void;
		onContinue: (chosen: BillableWorkItem[]) => void;
	} = $props();

	// Off until the dialog is actually open, then cached — reopening after a cancel is instant.
	const workQuery = createQuery(() => ({
		queryKey: billableWorkKey(clientId),
		queryFn: () => fetchBillableWork(clientId),
		enabled: open && Boolean(clientId),
		staleTime: 15_000
	}));

	const items = $derived(workQuery.data ?? []);

	let selected = $state<Set<string>>(new Set());
	// Seeded once per set of results rather than on every render, so a tick the contractor removes does not
	// come back the moment the query refetches.
	let seededFor = $state<string | null>(null);
	$effect(() => {
		if (!open) {
			seededFor = null;
			return;
		}
		const fingerprint = items.map((item) => item.job_id).join(',');
		if (seededFor === fingerprint) return;
		seededFor = fingerprint;
		const next = new Set<string>();
		if (initialJobId && items.some((item) => item.job_id === initialJobId)) next.add(initialJobId);
		selected = next;
	});

	function toggle(jobId: string) {
		const next = new Set(selected);
		if (next.has(jobId)) next.delete(jobId);
		else next.add(jobId);
		selected = next;
	}

	const chosen = $derived(items.filter((item) => selected.has(item.job_id)));

	// Differing tax rates split a bill in two, which this screen cannot do — Part 8's batch creation owns
	// that. Refusing the mixed selection here is honest; silently billing one rate would not be.
	const taxRateIds = $derived(new Set(chosen.map((item) => item.property_id ?? '')));
	const mixedProperties = $derived(chosen.length > 1 && taxRateIds.size > 1);

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	function amount(minor: number) {
		return money.format(minor / 100);
	}

	function addressOf(item: BillableWorkItem) {
		return [item.property_address_line1, item.property_city, item.property_state_region]
			.filter(Boolean)
			.join(', ');
	}

	function statusOf(item: BillableWorkItem) {
		const status = item.derived_status as JobDerivedStatus;
		return {
			label: JOB_STATUS_LABELS[status] ?? item.derived_status,
			tone: JOB_STATUS_TONES[status] ?? 'informative'
		};
	}
</script>

<Dialog {open} title={`Select work to invoice for ${clientName}`} size="large" onClose={onCancel}>
	<div class="select-work">
		{#if workQuery.isPending}
			<div class="select-work__skeleton" aria-hidden="true">
				{#each { length: 3 } as _, index (index)}
					<div class="select-work__skeleton-row"></div>
				{/each}
			</div>
		{:else if workQuery.isError}
			<p class="select-work__empty">That work could not be loaded. Close this and try again.</p>
		{:else if items.length === 0}
			<p class="select-work__empty">
				Every job for this client has already been billed. You can still write an invoice by hand.
			</p>
		{:else}
			<div class="select-work__scroll">
				<table class="select-work__table">
					<thead>
						<tr>
							<th scope="col"><span class="select-work__sr">Choose</span></th>
							<th scope="col">Status</th>
							<th scope="col">Job</th>
							<th scope="col">Address</th>
							<th scope="col" class="select-work__num">Uninvoiced</th>
							<th scope="col" class="select-work__num">Subtotal</th>
						</tr>
					</thead>
					<tbody>
						{#each items as item (item.job_id)}
							{@const status = statusOf(item)}
							<tr class:select-work__row--on={selected.has(item.job_id)}>
								<td>
									<Checkbox
										id={`select-work-${item.job_id}`}
										checked={selected.has(item.job_id)}
										onchange={() => toggle(item.job_id)}
										label={`Invoice job #${item.job_number} ${item.title}`}
										hideLabel
									/>
								</td>
								<td><StatusBadge status={status.tone}>{status.label}</StatusBadge></td>
								<td>
									<span class="select-work__title">#{item.job_number} {item.title}</span>
									{#if item.last_visit_date}
										<span class="select-work__meta">Visit: {item.last_visit_date}</span>
									{:else}
										<span class="select-work__meta">No visits yet</span>
									{/if}
								</td>
								<td class="select-work__address">{addressOf(item) || '—'}</td>
								<td class="select-work__num">{amount(item.uninvoiced_minor)}</td>
								<td class="select-work__num">{amount(item.subtotal_minor)}</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}

		{#if mixedProperties}
			<p class="select-work__warning">
				Those jobs are at different properties, which can mean different tax rates. Bill them one
				property at a time.
			</p>
		{/if}

		<footer class="select-work__actions">
			<Button variant="secondary" onclick={onCancel}>Cancel</Button>
			<Button
				variant="primary"
				disabled={chosen.length === 0 || mixedProperties}
				onclick={() => onContinue(chosen)}
			>
				Continue
			</Button>
		</footer>
	</div>
</Dialog>

<style lang="scss">
	.select-work {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__scroll {
			overflow-x: auto;
		}

		&__table {
			width: 100%;
			border-collapse: collapse;
			font-size: var(--typography--fontSize-base);

			th {
				padding: var(--space-smaller) var(--space-small);
				border-bottom: var(--border-base) solid var(--color-border);
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				font-weight: 600;
				text-align: left;
				white-space: nowrap;
			}

			td {
				padding: var(--space-small);
				border-bottom: var(--border-base) solid var(--color-border);
				vertical-align: middle;
			}
		}

		&__row--on {
			background: var(--color-surface--hover);
		}

		&__title {
			display: block;
			color: var(--color-text);
			font-weight: 600;
		}

		&__meta {
			display: block;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__address {
			color: var(--color-text--secondary);
		}

		&__num {
			text-align: right;
			font-variant-numeric: tabular-nums;
			white-space: nowrap;
		}

		&__empty {
			margin: 0;
			padding: var(--space-large) 0;
			color: var(--color-text--secondary);
			text-align: center;
		}

		&__warning {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-text);
			background: var(--warning-surface);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			padding-top: var(--space-small);
		}

		&__sr {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip-path: inset(50%);
			white-space: nowrap;
		}

		&__skeleton {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__skeleton-row {
			height: 44px;
			border-radius: var(--radius-base);
			background: var(--color-surface--hover);
		}
	}
</style>
