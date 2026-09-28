<script lang="ts">
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import RecordDetailLayout from '$lib/components/layout/RecordDetailLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import WorkRecordHeader from '$lib/components/work/WorkRecordHeader.svelte';
	import ClientSummaryCard from '$lib/components/work/ClientSummaryCard.svelte';
	import RecordFactsList from '$lib/components/work/RecordFactsList.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import RefundPaymentDialog from '$lib/components/invoices/RefundPaymentDialog.svelte';
	import StripeRefundDialog from '$lib/components/invoices/StripeRefundDialog.svelte';
	import UnapplyPaymentDialog from '$lib/components/invoices/UnapplyPaymentDialog.svelte';
	import MovePaymentDialog from '$lib/components/invoices/MovePaymentDialog.svelte';
	import CollectPaymentDialog from '$lib/components/invoices/CollectPaymentDialog.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		fetchPayment,
		paymentDetailKey,
		sendPaymentReceipt,
		refundPayment,
		refundStripePayment,
		runPaymentAllocationAction,
		fixPayment,
		withdrawPayment,
		type FixPaymentInput,
		type InvoiceWriteError,
		type PaymentAllocationEntry
	} from '$lib/invoices/api';
	import { INVOICE_PAYMENT_METHOD_LABELS } from '$lib/invoices/payment-methods';
	import cashIcon from '@tabler/icons/outline/cash.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import printIcon from '@tabler/icons/outline/printer.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import receiptRefundIcon from '@tabler/icons/outline/receipt-refund.svg?raw';
	import arrowBackIcon from '@tabler/icons/outline/arrow-back-up.svg?raw';
	import arrowsExchangeIcon from '@tabler/icons/outline/arrows-exchange.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import banIcon from '@tabler/icons/outline/ban.svg?raw';

	// One recorded payment. Jobber has this screen and Send Receipt lives on it, so ours is the same idea:
	// what was paid, how, against which bill, and the two things staff do with it afterwards — send the
	// customer their receipt again, or print it.
	//
	// Money already recorded is append-only in our ledger, so there is no pencil here and no save bar. Part 11
	// adds the three ledger-correction moves the header comment used to say belonged elsewhere: refund, take
	// off this invoice, and move to another invoice — each its own dialog, gated on can_correct_payment, none
	// of them editing or deleting the original entry.
	const toast = getToastManager();
	const queryClient = useQueryClient();

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
		const path = resolve('/(app)/payments/[id=uuid]/receipt', { id: paymentId });
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

	const isStripePayment = $derived(
		saved?.payment.method === 'stripe_card' ||
			saved?.payment.method === 'stripe_bank' ||
			saved?.payment.method === 'stripe_other'
	);

	// Fixed or marked never received (D7): the page becomes a record of the mistake, with nothing left to do.
	const isCorrected = $derived(Boolean(saved?.correction));
	const canCorrect = $derived(Boolean(saved?.can_correct_payment) && !isCorrected);
	const status = $derived.by(() => {
		if (!saved?.correction) return { label: 'Recorded', tone: 'success' as const };
		return saved.correction.replacement_payment_id
			? { label: 'Corrected', tone: 'warning' as const }
			: { label: 'Never received', tone: 'critical' as const };
	});

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
		},
		...(canCorrect && !isStripePayment
			? [
					{ label: 'Fix payment', icon: pencilIcon, onSelect: () => (fixOpen = true) },
					{
						label: 'Mark as never received',
						icon: banIcon,
						onSelect: () => (withdrawOpen = true)
					}
				]
			: []),
		...(canCorrect
			? [
					...(isStripePayment
						? [
								{
									label: 'Refund through Stripe',
									icon: receiptRefundIcon,
									onSelect: () => (stripeRefundOpen = true)
								}
							]
						: []),
					{ label: 'Refund payment', icon: receiptRefundIcon, onSelect: () => (refundOpen = true) }
				]
			: [])
	]);

	const clientMenuItems = $derived(
		saved?.client
			? [
					{
						label: 'View client profile',
						onSelect: () => void goto(resolve('/(app)/clients/[id=uuid]', { id: saved.client!.id }))
					}
				]
			: []
	);

	// --- Correcting the ledger (Part 11): refund, take off, move ------------------------------------------
	// Everything touched here can affect an invoice's status and remaining balance, so a successful correction
	// invalidates this payment plus the whole 'invoices' prefix (list, counts, and any open invoice detail)
	// rather than trying to name the exact rows that changed.
	async function afterCorrection(label: string, tone: 'success' | 'error' = 'success') {
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: paymentDetailKey(paymentId) }),
			queryClient.invalidateQueries({ queryKey: ['invoices'] })
		]);
		toast[tone](label);
	}

	let refundOpen = $state(false);
	let stripeRefundOpen = $state(false);

	function saveRefund(payload: Parameters<typeof refundPayment>[1]) {
		return refundPayment(paymentId, payload);
	}

	function saveStripeRefund(payload: Parameters<typeof refundStripePayment>[1]) {
		return refundStripePayment(paymentId, payload);
	}

	// --- Applied-to row actions -----------------------------------------------------------------------------
	let unapplyTarget = $state<PaymentAllocationEntry | null>(null);
	let moveTarget = $state<PaymentAllocationEntry | null>(null);

	function allocationMenuFor(entry: PaymentAllocationEntry) {
		if (!canCorrect) return [];
		if (entry.entry_type !== 'applied' || entry.is_reversed || !entry.invoice_id) return [];
		return [
			{
				label: 'Take off this invoice',
				icon: arrowBackIcon,
				onSelect: () => (unapplyTarget = entry)
			},
			{
				label: 'Move to another invoice',
				icon: arrowsExchangeIcon,
				onSelect: () => (moveTarget = entry)
			}
		];
	}

	function saveUnapply(reason: string | null, idempotencyKey: string, requestHash: string) {
		if (!unapplyTarget) return Promise.reject(new Error('No payment entry selected.'));
		return runPaymentAllocationAction(
			unapplyTarget.allocation_id,
			{ action: 'unapply', reason },
			idempotencyKey,
			requestHash
		);
	}

	// --- Fix payment / Mark as never received (D7) --------------------------------------------------------
	let fixOpen = $state(false);
	let withdrawOpen = $state(false);

	// The bills this payment is still on, each with what it would owe once this payment is taken off.
	const liveAllocations = $derived(
		(saved?.applied_to ?? []).filter(
			(entry) => entry.entry_type === 'applied' && !entry.is_reversed && entry.invoice_id
		)
	);
	const fixPinned = $derived(
		liveAllocations.map((entry) => ({
			id: entry.invoice_id!,
			number: entry.invoice_number,
			detail: entry.subject || 'Currently applied',
			owedMinor: (entry.invoice_remaining_minor ?? 0) + entry.amount_minor
		}))
	);

	function saveFix(payload: FixPaymentInput) {
		return fixPayment(paymentId, payload);
	}

	async function onFixed(result: { payment_event_id: string }) {
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: ['payments'] }),
			queryClient.invalidateQueries({ queryKey: ['invoices'] })
		]);
		toast.success('Payment fixed');
		await goto(resolve('/(app)/payments/[id=uuid]', { id: result.payment_event_id }));
	}

	function saveWithdraw(reason: string | null, idempotencyKey: string, requestHash: string) {
		return withdrawPayment(paymentId, {
			reason,
			idempotency_key: idempotencyKey,
			request_hash: requestHash
		});
	}

	function saveMove(
		targetInvoiceId: string,
		amountMinor: number | null,
		reason: string | null,
		idempotencyKey: string,
		requestHash: string
	) {
		if (!moveTarget) return Promise.reject(new Error('No payment entry selected.'));
		return runPaymentAllocationAction(
			moveTarget.allocation_id,
			{ action: 'move', target_invoice_id: targetInvoiceId, amount_minor: amountMinor, reason },
			idempotencyKey,
			requestHash
		);
	}
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
					statusLabel={status.label}
					statusTone={status.tone}
					{menuItems}
					primaryAction={saved.can_send_receipt && !isCorrected
						? { label: 'Send receipt', loading: sending, onclick: () => void sendReceipt() }
						: undefined}
				>
					{#snippet summary()}
						<ClientSummaryCard
							name={clientName}
							href={saved.client
								? resolve('/(app)/clients/[id=uuid]', { id: saved.client.id })
								: undefined}
							email={saved.client?.email ?? null}
							menuItems={clientMenuItems}
						/>
					{/snippet}
					{#snippet facts()}<RecordFactsList facts={headerFacts} />{/snippet}
				</WorkRecordHeader>

				{#if saved.correction}
					<div class="payment-detail__correction" role="note">
						<p class="payment-detail__correction-title">
							{saved.correction.replacement_payment_id ? 'Fixed on' : 'Marked as never received on'}
							{dateTimeFormat.format(new Date(saved.correction.corrected_at))}
						</p>
						{#if saved.correction.note}
							<p class="payment-detail__correction-note">{saved.correction.note}</p>
						{/if}
						{#if saved.correction.replacement_payment_id}
							<a
								class="payment-detail__correction-link"
								href={resolve('/(app)/payments/[id=uuid]', {
									id: saved.correction.replacement_payment_id
								})}
							>
								View the corrected payment
							</a>
						{/if}
					</div>
				{:else if saved.replaces_payment_id}
					<div class="payment-detail__correction payment-detail__correction--info" role="note">
						<p class="payment-detail__correction-note">This payment corrects an earlier one.</p>
						<a
							class="payment-detail__correction-link"
							href={resolve('/(app)/payments/[id=uuid]', { id: saved.replaces_payment_id })}
						>
							View the original
						</a>
					</div>
				{/if}

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
												href={resolve('/(app)/invoices/[id=uuid]', { id: entry.invoice_id })}
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
									{#if allocationMenuFor(entry).length > 0}
										<DropdownMenu
											triggerLabel="Actions for invoice #{entry.invoice_number}"
											items={allocationMenuFor(entry)}
										/>
									{/if}
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

		{#if refundOpen}
			<RefundPaymentDialog
				open={refundOpen}
				amountMinor={saved.payment.amount_minor}
				currencyCode={saved.payment.currency_code}
				locale={saved.locale}
				onClose={() => (refundOpen = false)}
				onSave={saveRefund}
				onSaved={() => afterCorrection('Payment refunded')}
			/>
		{/if}

		{#if stripeRefundOpen}
			<StripeRefundDialog
				open={stripeRefundOpen}
				amountMinor={saved.payment.amount_minor}
				currencyCode={saved.payment.currency_code}
				locale={saved.locale}
				onClose={() => (stripeRefundOpen = false)}
				onSave={saveStripeRefund}
				onSaved={(result) =>
					result.status === 'failed'
						? afterCorrection(
								'Stripe could not send this refund — check your Stripe dashboard',
								'error'
							)
						: afterCorrection(
								result.status === 'succeeded'
									? 'Payment refunded through Stripe'
									: 'Refund sent — Stripe is still confirming it'
							)}
			/>
		{/if}

		{#if fixOpen && saved.client}
			<CollectPaymentDialog
				open
				mode="fix"
				clientId={saved.client.id}
				pinned={fixPinned}
				initial={{
					amountMinor: saved.payment.amount_minor,
					method: saved.payment.method as FixPaymentInput['method'],
					paymentDate: saved.payment.payment_date,
					reference: saved.payment.reference,
					note: saved.payment.note,
					applied: Object.fromEntries(
						liveAllocations.map((entry) => [entry.invoice_id!, entry.amount_minor])
					)
				}}
				currencyCode={saved.payment.currency_code}
				locale={saved.locale}
				onClose={() => (fixOpen = false)}
				onSave={saveFix}
				onSaved={(result) => onFixed(result)}
			/>
		{/if}

		{#if withdrawOpen}
			<UnapplyPaymentDialog
				open
				invoiceNumber={0}
				amountMinor={saved.payment.amount_minor}
				currencyCode={saved.payment.currency_code}
				locale={saved.locale}
				copy={{
					title: 'Mark this payment as never received?',
					intro:
						'it comes off every invoice it is on, so they owe it again. The payment stays in history, marked as never received.',
					confirmLabel: 'Mark as never received',
					icon: banIcon,
					critical: true
				}}
				onClose={() => (withdrawOpen = false)}
				onSave={saveWithdraw}
				onSaved={() => afterCorrection('Payment marked as never received')}
			/>
		{/if}

		{#if unapplyTarget}
			<UnapplyPaymentDialog
				open={Boolean(unapplyTarget)}
				invoiceNumber={unapplyTarget.invoice_number}
				amountMinor={unapplyTarget.amount_minor}
				currencyCode={saved.payment.currency_code}
				locale={saved.locale}
				onClose={() => (unapplyTarget = null)}
				onSave={saveUnapply}
				onSaved={() => afterCorrection('Payment taken off the invoice')}
			/>
		{/if}

		{#if moveTarget && saved.client}
			<MovePaymentDialog
				open={Boolean(moveTarget)}
				clientId={saved.client.id}
				currentInvoiceId={moveTarget.invoice_id ?? ''}
				allocation={{
					invoiceNumber: moveTarget.invoice_number,
					amountMinor: moveTarget.amount_minor
				}}
				currencyCode={saved.payment.currency_code}
				locale={saved.locale}
				onClose={() => (moveTarget = null)}
				onSave={saveMove}
				onSaved={() => afterCorrection('Payment moved')}
			/>
		{/if}
	{/if}
</PageContainer>

<style lang="scss">
	.payment-detail__correction {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-left: 3px solid var(--color-warning);
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);
	}

	.payment-detail__correction--info {
		border-left-color: var(--color-interactive);
	}

	.payment-detail__correction-title {
		margin: 0;
		font-weight: 600;
		color: var(--color-heading);
	}

	.payment-detail__correction-note {
		margin: 0;
		white-space: pre-wrap;
		color: var(--color-text--secondary);
	}

	.payment-detail__correction-link {
		align-self: flex-start;
		font-weight: 600;
		color: var(--color-interactive);

		&:hover {
			text-decoration: underline;
		}
	}

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
		align-items: center;
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
