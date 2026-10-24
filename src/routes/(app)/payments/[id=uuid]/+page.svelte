<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import RecordDetailLayout from '$lib/components/layout/RecordDetailLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import WorkRecordHeader from '$lib/components/work/WorkRecordHeader.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import PaymentReceiptCard from '$lib/components/invoices/PaymentReceiptCard.svelte';
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
	import printIcon from '@tabler/icons/outline/printer.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import receiptRefundIcon from '@tabler/icons/outline/receipt-refund.svg?raw';
	import arrowBackIcon from '@tabler/icons/outline/arrow-back-up.svg?raw';
	import arrowsExchangeIcon from '@tabler/icons/outline/arrows-exchange.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import banIcon from '@tabler/icons/outline/ban.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import creditCardIcon from '@tabler/icons/outline/credit-card.svg?raw';
	import hashIcon from '@tabler/icons/outline/hash.svg?raw';

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
	// A plain `if`/`return`, not a ternary: checking resolve()'s own route-id type together with
	// `undefined` in one conditional expression is what tips TypeScript over its complexity limit
	// (svelte-check: "union type that is too complex to represent"). A separate return per branch
	// checks each one on its own instead.
	const clientHref = $derived.by((): string | undefined => {
		if (!saved?.client) return undefined;
		return resolve('/(app)/clients/[id=uuid]', { id: saved.client.id });
	});

	const dateFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	});
	const shortDateFormat = new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short' });
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
	// The header's facts leave the year off for this year's dates ("Oct 9"), as the design does, and keep it
	// for any other year so an old payment is never mistaken for a recent one.
	const thisYear = new Date().getFullYear();
	const factDayFormat = new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short' });
	function factDay(value: string) {
		const date = new Date(`${value}T00:00`);
		return date.getFullYear() === thisYear ? factDayFormat.format(date) : formatDay(value);
	}
	function formatShortDay(value: string) {
		return shortDateFormat.format(new Date(`${value}T00:00`));
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

	// The bills this payment is still on, each with what it would owe once this payment is taken off.
	const liveAllocations = $derived(
		(saved?.applied_to ?? []).filter(
			(entry) => entry.entry_type === 'applied' && !entry.is_reversed && entry.invoice_id
		)
	);

	// Paid on · Method · Reference # · For invoice #, as Jobber shows them.
	const headerFacts = $derived([
		{
			label: 'Paid on',
			value: saved ? factDay(saved.payment.payment_date) : null,
			icon: calendarIcon,
			kind: 'time' as const
		},
		{
			label: 'Method',
			value: saved ? INVOICE_PAYMENT_METHOD_LABELS[saved.payment.method] : null,
			icon: creditCardIcon,
			kind: 'invoice' as const
		},
		{
			label: 'Reference #',
			value: saved?.payment.reference ?? null,
			empty: 'None given',
			icon: hashIcon,
			kind: 'invoice' as const
		},
		{
			label: liveAllocations.length > 1 ? 'For invoices #' : 'For invoice #',
			value: liveAllocations.map((entry) => entry.invoice_number).join(', ') || null,
			empty: 'Not on an invoice',
			icon: receiptIcon,
			kind: 'time' as const
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

	// The receipt card draws what the customer's email says, from this payment's own figures.
	const clientFirstName = $derived(
		(saved?.client?.display_name || saved?.client?.company_name || '').trim().split(/\s+/)[0] || ''
	);
	const receiptLines = $derived.by(() => {
		if (!saved) return [];
		const payment = saved.payment;
		const lines = [
			{
				icon: cashIcon,
				text: `${formatMoney(payment.amount_minor)} paid on ${formatShortDay(payment.payment_date)}`
			},
			{
				icon: creditCardIcon,
				text: [
					INVOICE_PAYMENT_METHOD_LABELS[payment.method],
					payment.reference && `Ref ${payment.reference}`
				]
					.filter(Boolean)
					.join(' · ')
			},
			...liveAllocations.map((entry) => ({
				icon: receiptIcon,
				text: `Invoice #${entry.invoice_number} · ${formatMoney(entry.amount_minor)}`
			}))
		];
		return lines;
	});
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

<PageContainer variant="open">
	{#if paymentQuery.isPending}
		<LoadingSkeleton variant="card" label="Loading payment" />
	{:else if paymentQuery.isError}
		<ErrorState description="That payment could not be loaded. Refresh and try again." />
	{:else if saved}
		<RecordDetailLayout class="payment-detail" cards concept>
			{#snippet main()}
				<WorkRecordHeader
					icon={creditCardIcon}
					recordType="Payment"
					title={formatMoney(saved.payment.amount_minor)}
					statusLabel={status.label}
					statusTone={status.tone}
					{menuItems}
					primaryAction={saved.can_send_receipt && !isCorrected
						? {
								label: 'Send receipt',
								icon: mailIcon,
								loading: sending,
								onclick: () => void sendReceipt()
							}
						: undefined}
					client={{
						name: clientName,
						href: clientHref,
						avatarId: saved.client?.id,
						email: saved.client?.email ?? null,
						hideAddress: true,
						hidePhone: true
					}}
					facts={headerFacts}
				/>

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

				<SectionBlock
					tone="invoice"
					title="Applied to"
					hint="The invoices this money paid"
					level={2}
					class="section-block--flush payment-detail__card"
				>
					{#if saved.applied_to.length}
						<ul class="payment-detail__applied">
							{#each saved.applied_to as entry (entry.allocation_id)}
								<li class="payment-detail__applied-row">
									<IconTile icon={receiptIcon} tone="informative" size={32} />
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
											{[
												entry.entry_type === 'unapplied' ? 'Taken off this bill' : entry.subject,
												dateFormat.format(new Date(entry.created_at))
											]
												.filter(Boolean)
												.join(' \u00b7 ')}
										</span>
									</div>
									<span
										class="payment-detail__applied-amount"
										class:payment-detail__applied-amount--negative={entry.entry_type ===
											'unapplied'}
									>
										{entry.entry_type === 'unapplied' ? '\u2212' : ''}{formatMoney(
											entry.amount_minor
										)}
									</span>
									{#if allocationMenuFor(entry).length > 0}
										<DropdownMenu
											triggerLabel="Actions for invoice #{entry.invoice_number}"
											items={allocationMenuFor(entry)}
										/>
									{:else}
										<span class="payment-detail__applied-spacer" aria-hidden="true"></span>
									{/if}
								</li>
							{/each}
						</ul>
					{:else}
						<p class="payment-detail__quiet">
							Not applied to a bill. This money sits on the client's account as credit.
						</p>
					{/if}
				</SectionBlock>

				<SectionBlock
					tone="invoice"
					title="Details"
					hint="Noted when this payment was recorded"
					level={2}
					class="section-block--flush payment-detail__card"
				>
					{#if saved.payment.note}
						<p class="payment-detail__note">{saved.payment.note}</p>
					{:else}
						<p class="payment-detail__quiet">Nothing was noted when this payment was recorded.</p>
					{/if}
				</SectionBlock>
			{/snippet}

			{#snippet rail()}
				<PaymentReceiptCard
					businessName={page.data.organization?.name ?? 'Your business'}
					logoUrl={page.data.logoUrl ?? null}
					recipient={clientFirstName || 'your client'}
					tagline={clientFirstName
						? `Payment received \u2014 thank you, ${clientFirstName}.`
						: 'Payment received \u2014 thank you.'}
					lines={receiptLines}
					onView={() => openReceipt()}
					onPrint={() => openReceipt(true)}
				/>
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
				clientName={saved.client.display_name ?? ''}
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
		background: var(--color-surface);
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

	// The card's own header (title and one-line hint) comes from the shared block; these rows and the note run
	// edge to edge beneath it, one hairline apart.
	.payment-detail__note {
		margin: 0;
		padding: 16px 24px 22px;
		border-top: var(--border-base) solid var(--color-border);
		color: var(--color-text);
		line-height: 1.6;
		white-space: pre-wrap;
		overflow-wrap: anywhere;
	}

	.payment-detail__quiet {
		margin: 0;
		padding: 16px 24px 22px;
		border-top: var(--border-base) solid var(--color-border);
		color: var(--color-text--secondary);
	}

	.payment-detail__applied {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
	}

	.payment-detail__applied-row {
		display: flex;
		align-items: center;
		gap: 14px;
		padding: 14px 24px;
		border-top: var(--border-base) solid var(--color-border);
	}

	.payment-detail__applied-main {
		display: flex;
		flex: 1;
		flex-direction: column;
		gap: 3px;
		min-width: 0;
	}

	.payment-detail__applied-link {
		font-weight: 600;
		color: var(--color-heading);
	}

	a.payment-detail__applied-link {
		color: var(--color-interactive);
		text-decoration: none;

		&:hover {
			text-decoration: underline;
		}

		&:focus-visible {
			outline: none;
			border-radius: var(--radius-small);
			box-shadow: var(--shadow-focus);
		}
	}

	.payment-detail__applied-meta {
		overflow: hidden;
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
		color: var(--color-text--secondary);
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.payment-detail__applied-amount {
		flex: 0 0 110px;
		font-weight: 700;
		text-align: right;
		white-space: nowrap;
		color: var(--color-heading);
	}

	.payment-detail__applied-amount--negative {
		color: var(--color-critical);
	}

	.payment-detail__applied-spacer {
		flex: 0 0 32px;
	}

	// The row's `...` button wears the app's quiet outline, as the other cards' row actions do.
	.payment-detail__applied-row :global(.dropdown-menu__trigger) {
		border: var(--border-base) solid var(--color-border--interactive);
		background: var(--color-surface);
	}

	@media (max-width: 767px) {
		.payment-detail__applied-row {
			padding-inline: 16px;
		}
		.payment-detail__applied-amount {
			flex-basis: auto;
		}
		.payment-detail__note,
		.payment-detail__quiet {
			padding-inline: 16px;
		}
	}
</style>
