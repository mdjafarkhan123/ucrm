<script lang="ts">
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { createQuery } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import RecordDetailLayout from '$lib/components/layout/RecordDetailLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import WorkRecordHeader from '$lib/components/work/WorkRecordHeader.svelte';
	import ClientSummaryCard from '$lib/components/work/ClientSummaryCard.svelte';
	import RecordFactsList from '$lib/components/work/RecordFactsList.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		fetchPayment,
		paymentDetailKey,
		sendPaymentReceipt,
		type InvoiceWriteError
	} from '$lib/invoices/api';
	import { INVOICE_PAYMENT_METHOD_LABELS } from '$lib/invoices/payment-methods';
	import cashIcon from '@tabler/icons/outline/cash.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import printIcon from '@tabler/icons/outline/printer.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';

	// One recorded payment. Jobber has this screen and Send Receipt lives on it, so ours is the same idea:
	// what was paid, how, against which bill, and the two things staff do with it afterwards — send the
	// customer their receipt again, or print it.
	//
	// It is read-only on purpose. Money already recorded is append-only in our ledger, so there is no pencil
	// here and no save bar; editing or reversing a payment is ledger-correction work of its own.
	const toast = getToastManager();

	const paymentId = $derived(page.params.id ?? '');

	const paymentQuery = createQuery(() => ({
		queryKey: paymentDetailKey(paymentId),
		queryFn: () => fetchPayment(paymentId),
		enabled: Boolean(paymentId)
	}));
	const saved = $derived(paymentQuery.data);

	const dateFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	});
	const dateTimeFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		year: 'numeric',
		hour: 'numeric',
		minute: '2-digit'
	});
	// A `date` column arrives as `YYYY-MM-DD`; `new Date` on that reads it as UTC midnight and shifts the day
	// backwards for anybody west of Greenwich. The local-midnight form keeps the day the contractor picked.
	function formatDay(value: string) {
		return dateFormat.format(new Date(`${value}T00:00`));
	}
	const money = $derived(
		new Intl.NumberFormat(saved?.locale ?? 'en-US', {
			style: 'currency',
			currency: saved?.payment.currency_code ?? 'USD'
		})
	);
	function formatMoney(amountMinor: number) {
		return money.format(amountMinor / 100);
	}

	const clientName = $derived(
		saved?.client?.company_name || saved?.client?.display_name || 'No client'
	);

	const headerFacts = $derived([
		{
			label: 'Transaction date',
			value: saved ? formatDay(saved.payment.payment_date) : null
		},
		{
			label: 'Method',
			value: saved ? INVOICE_PAYMENT_METHOD_LABELS[saved.payment.method] : null
		},
		{ label: 'Reference #', value: saved?.payment.reference ?? null, empty: 'None given' },
		{
			label: 'Recorded',
			value: saved ? dateTimeFormat.format(new Date(saved.payment.created_at)) : null
		}
	]);

	// The customer's own receipt, in its own tab, with our sidebar left behind. `print` asks that tab to open
	// the print dialog as soon as it has drawn, so `Print or save PDF` is one press — the same as invoices.
	function openReceipt(print = false) {
		if (!paymentId) return;
		const path = resolve('/(app)/payments/[id]/receipt', { id: paymentId });
		window.open(print ? `${path}?print=1` : path, '_blank', 'noopener');
	}

	let sending = $state(false);

	async function sendReceipt() {
		if (!saved || sending) return;
		sending = true;
		try {
			await sendPaymentReceipt(saved.payment.id, crypto.randomUUID());
			toast.success('Receipt emailed');
		} catch (cause) {
			toast.error((cause as InvoiceWriteError).message);
		} finally {
			sending = false;
		}
	}

	const menuItems = $derived([
		{
			label: 'View receipt',
			icon: receiptIcon,
			onSelect: () => openReceipt()
		},
		{
			label: 'Print or save PDF',
			icon: printIcon,
			onSelect: () => openReceipt(true)
		}
	]);

	const clientMenuItems = $derived(
		saved?.client
			? [
					{
						label: 'View client profile',
						onSelect: () => void goto(resolve('/(app)/clients/[id]', { id: saved.client!.id }))
					}
				]
			: []
	);
</script>

<svelte:head>
	<title>Payment</title>
</svelte:head>

<PageContainer>
	{#if paymentQuery.isPending}
		<LoadingSkeleton variant="card" label="Loading payment" />
	{:else if paymentQuery.isError}
		<ErrorState description="That payment could not be loaded. Refresh and try again." />
	{:else if saved}
		<RecordDetailLayout class="payment-detail">
			{#snippet main()}
				<WorkRecordHeader
					icon={cashIcon}
					recordType="Payment"
					title={formatMoney(saved.payment.amount_minor)}
					statusLabel="Recorded"
					statusTone="success"
					{menuItems}
					primaryAction={saved.can_send_receipt
						? { label: 'Send receipt', loading: sending, onclick: () => void sendReceipt() }
						: undefined}
				>
					{#snippet summary()}
						<ClientSummaryCard
							name={clientName}
							href={saved.client
								? resolve('/(app)/clients/[id]', { id: saved.client.id })
								: undefined}
							email={saved.client?.email ?? null}
							menuItems={clientMenuItems}
						/>
					{/snippet}
					{#snippet facts()}<RecordFactsList facts={headerFacts} />{/snippet}
				</WorkRecordHeader>

				<SectionBlock title="Details" icon={fileTextIcon} level={2}>
					{#if saved.payment.note}
						<p class="payment-detail__note">{saved.payment.note}</p>
					{:else}
						<EmptyState
							icon={fileTextIcon}
							title="No details"
							description="Nothing was noted when this payment was recorded."
						/>
					{/if}
				</SectionBlock>

				<SectionBlock title="Applied to" icon={receiptIcon} level={2}>
					{#if saved.applied_to.length}
						<ul class="payment-detail__applied">
							{#each saved.applied_to as entry (entry.allocation_id)}
								<li class="payment-detail__applied-row">
									<div class="payment-detail__applied-main">
										{#if entry.invoice_id}
											<a
												class="payment-detail__applied-link"
												href={resolve('/(app)/invoices/[id]', { id: entry.invoice_id })}
											>
												Invoice #{entry.invoice_number}
											</a>
										{:else}
											<span class="payment-detail__applied-link">
												Invoice #{entry.invoice_number}
											</span>
										{/if}
										<span class="payment-detail__applied-meta">
											{entry.entry_type === 'unapplied' ? 'Taken off this bill' : entry.subject}
											&middot; {dateFormat.format(new Date(entry.created_at))}
										</span>
									</div>
									<span
										class="payment-detail__applied-amount"
										class:payment-detail__applied-amount--negative={entry.entry_type ===
											'unapplied'}
									>
										{entry.entry_type === 'unapplied' ? '−' : ''}{formatMoney(entry.amount_minor)}
									</span>
								</li>
							{/each}
						</ul>
					{:else}
						<EmptyState
							icon={receiptIcon}
							title="Not applied to a bill"
							description="This money sits on the client's account as credit."
						/>
					{/if}
				</SectionBlock>
			{/snippet}
		</RecordDetailLayout>
	{/if}
</PageContainer>

<style lang="scss">
	.payment-detail__note {
		margin: 0;
		white-space: pre-wrap;
		color: var(--color-text);
	}

	.payment-detail__applied {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.payment-detail__applied-row {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.payment-detail__applied-main {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		min-width: 0;
	}

	.payment-detail__applied-link {
		font-weight: 600;
		color: var(--color-heading);
	}

	a.payment-detail__applied-link {
		color: var(--color-interactive);

		&:hover {
			text-decoration: underline;
		}
	}

	.payment-detail__applied-meta {
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.payment-detail__applied-amount {
		flex-shrink: 0;
		font-weight: 600;
		white-space: nowrap;
		color: var(--color-heading);
	}

	.payment-detail__applied-amount--negative {
		color: var(--color-critical);
	}
</style>
