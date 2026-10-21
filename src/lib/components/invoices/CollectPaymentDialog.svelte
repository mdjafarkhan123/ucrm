<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { untrack } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import MoneyInput from '$lib/components/forms/MoneyInput.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import cardIcon from '@tabler/icons/outline/credit-card.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import bankIcon from '@tabler/icons/outline/building-bank.svg?raw';
	import hashIcon from '@tabler/icons/outline/hash.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import errorIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import { calendarDateFromString, calendarDateToString } from '$lib/components/ui/date-time';
	import {
		INVOICE_PAYMENT_METHOD_OPTIONS,
		type InvoicePaymentMethod
	} from '$lib/invoices/payment-methods';
	import {
		clientOpenInvoicesKey,
		fetchClientOpenInvoices,
		type InvoiceWriteError,
		type RecordInvoicePaymentInput,
		type RecordInvoicePaymentResult
	} from '$lib/invoices/api';

	// One received payment spread across a client's bills, Jobber's New Payment shape (D8). Two modes share it:
	//   * collect — the bill the dialog was opened from is pinned and ticked first; the client's other issued
	//     bills that still owe are listed under it.
	//   * fix — Fix payment (D7): the form opens prefilled with the mistyped payment, its bills pinned with
	//     what they would owe once it is taken off, and saving records the corrected payment in its place.
	// Whatever is not applied stays with the client as credit. The dialog owns its fields and validation; the
	// page owns the write and what happens after (invalidate, toast). The database re-checks every bill.
	type PinnedInvoice = {
		id: string;
		number: number;
		/** Short line under the number, e.g. "This invoice". */
		detail: string;
		/** The most this payment may put on the bill. */
		owedMinor: number;
	};
	type PaymentPayload = Omit<RecordInvoicePaymentInput, 'client_id' | 'allocations'> & {
		allocations: { invoice_id: string; amount_minor: number }[];
		reason: string | null;
	};

	let {
		open,
		mode = 'collect',
		clientId,
		pinned,
		initial,
		currencyCode,
		locale,
		clientName = '',
		onClose,
		onSave,
		onSaved
	}: {
		open: boolean;
		mode?: 'collect' | 'fix';
		clientId: string;
		pinned: PinnedInvoice[];
		/** Prefill. Without it the amount is what the pinned bills owe, each ticked in full. */
		initial?: {
			amountMinor: number;
			method: InvoicePaymentMethod;
			paymentDate: string;
			reference: string | null;
			note: string | null;
			applied: Record<string, number>;
		};
		currencyCode: string;
		locale: string;
		/** Named in the quiet line under the title, with the invoice (or, when fixing, the payment). */
		clientName?: string;
		onClose: () => void;
		onSave: (payload: PaymentPayload) => Promise<RecordInvoicePaymentResult>;
		/** Handed the recorded payment and whether staff asked for the customer's receipt to go out with it.
		 *  Emailing is the page's job, not this form's: the money is already recorded by the time this runs,
		 *  so a receipt that fails to send must never read as a payment that failed. */
		onSaved: (result: RecordInvoicePaymentResult, emailReceipt: boolean) => void | Promise<void>;
	} = $props();

	const fixing = $derived(mode === 'fix');

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	const dueFormat = $derived(new Intl.DateTimeFormat(locale, { month: 'short', day: 'numeric' }));

	// The same cache the Move dialog reads; the page prefetches it when the button that opens this is reached.
	const openInvoicesQuery = createQuery(() => ({
		queryKey: clientOpenInvoicesKey(clientId),
		queryFn: () => fetchClientOpenInvoices(clientId, pinned[0]?.id ?? ''),
		enabled: open && Boolean(clientId),
		staleTime: 15_000
	}));

	// Other bills this payment can settle: issued, still owing, same currency, not already pinned. Drafts are
	// left out — they are not yet owed (D1) and are paid from their own page.
	const otherInvoices = $derived(
		(openInvoicesQuery.data ?? []).filter(
			(invoice) =>
				!pinned.some((entry) => entry.id === invoice.id) &&
				invoice.derived_status !== 'draft' &&
				invoice.currency_code === currencyCode &&
				(invoice.remaining_minor ?? 0) > 0
		)
	);

	function todayIso() {
		const now = new Date();
		return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(
			now.getDate()
		).padStart(2, '0')}`;
	}

	// A short, stable fingerprint of what is being submitted — the same FNV-1a shape every invoice write on
	// this page uses, so a retry of the exact same payment replays instead of double-recording it.
	function fingerprint(value: unknown): string {
		const json = JSON.stringify(value);
		let hash = 0x811c9dc5;
		for (let index = 0; index < json.length; index++) {
			hash ^= json.charCodeAt(index);
			hash = Math.imul(hash, 0x01000193);
		}
		return `v1:${(hash >>> 0).toString(16)}`;
	}

	// The page mounts this component only while `collectPaymentOpen` is true (the same `{#if}`-gated shape
	// InvoiceEmailDialog uses), so a fresh instance — and fresh state below — is what "opening the dialog"
	// already means. No reset effect is needed.
	let amountMinor = $state(
		untrack(() => initial?.amountMinor ?? pinned.reduce((sum, entry) => sum + entry.owedMinor, 0))
	);
	let method = $state<InvoicePaymentMethod>(untrack(() => initial?.method ?? 'other'));
	let paymentDate = $state(untrack(() => initial?.paymentDate ?? todayIso()));
	let reference = $state(untrack(() => initial?.reference ?? ''));
	let note = $state(untrack(() => initial?.note ?? ''));
	let reason = $state('');
	// Ticked bills and what each gets, by invoice id.
	let applied = $state<Record<string, number>>(
		untrack(
			() =>
				initial?.applied ?? Object.fromEntries(pinned.map((entry) => [entry.id, entry.owedMinor]))
		)
	);
	// Which button is in flight, so only the pressed one spins. Both write the same payment; they differ only
	// in whether the customer is emailed afterwards.
	let savingMode = $state<'save' | 'receipt' | null>(null);
	const saving = $derived(savingMode !== null);
	let error = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let idempotencyKey = crypto.randomUUID();
	let lastHash = '';

	function numberOf(id: string) {
		return (
			pinned.find((entry) => entry.id === id)?.number ??
			otherInvoices.find((invoice) => invoice.id === id)?.invoice_number
		);
	}

	function balanceOf(id: string) {
		const pin = pinned.find((entry) => entry.id === id);
		if (pin) return pin.owedMinor;
		return otherInvoices.find((invoice) => invoice.id === id)?.remaining_minor ?? 0;
	}

	const subtitle = $derived(
		[
			fixing
				? `${money.format((initial?.amountMinor ?? amountMinor) / 100)} payment`
				: pinned[0]
					? `Invoice #${pinned[0].number}`
					: '',
			clientName
		]
			.filter(Boolean)
			.join(' · ')
	);

	const appliedMinor = $derived(Object.values(applied).reduce((sum, value) => sum + value, 0));
	const creditMinor = $derived(Math.max(amountMinor - appliedMinor, 0));
	// The foot card's bar: blue for what is applied, sand for what stays as credit.
	const appliedShare = $derived(
		appliedMinor + creditMinor > 0 ? appliedMinor / (appliedMinor + creditMinor) : 1
	);

	// A new total is spread again over the ticked bills, pinned ones first, each up to what it owes — so typing
	// the transfer amount is usually all staff need to do.
	function setAmount(value: number) {
		amountMinor = value;
		let left = value;
		const next: Record<string, number> = {};
		for (const id of [
			...pinned.map((entry) => entry.id),
			...otherInvoices.map((invoice) => invoice.id)
		]) {
			if (!(id in applied)) continue;
			next[id] = Math.min(balanceOf(id), left);
			left -= next[id];
		}
		applied = next;
	}

	// Ticking a bill gives it what it owes, from whatever is not yet applied.
	function toggle(id: string, checked: boolean) {
		const next = { ...applied };
		if (checked) {
			next[id] = Math.min(balanceOf(id), Math.max(amountMinor - appliedMinor, 0));
		} else {
			delete next[id];
		}
		applied = next;
	}

	function close() {
		if (saving) return;
		onClose();
	}

	function validate(): Record<string, string> {
		const errors: Record<string, string> = {};
		if (!amountMinor || amountMinor <= 0) {
			errors.amount_minor = 'Enter how much was paid.';
			return errors;
		}
		for (const [id, value] of Object.entries(applied)) {
			if (value <= 0) errors[`applied_${id}`] = 'Enter an amount or untick this invoice.';
			else if (value > balanceOf(id))
				errors[`applied_${id}`] = `That is more than #${numberOf(id)} owes.`;
		}
		if (appliedMinor > amountMinor) {
			errors.amount_minor = 'The invoices add up to more than the payment received.';
		}
		return errors;
	}

	async function submit(emailReceipt: boolean) {
		if (saving) return;
		error = '';
		fieldErrors = validate();
		if (Object.keys(fieldErrors).length) return;

		const core = {
			amount_minor: amountMinor,
			method,
			payment_date: paymentDate,
			reference: reference.trim() || null,
			note: note.trim() || null,
			allocations: Object.entries(applied).map(([id, value]) => ({
				invoice_id: id,
				amount_minor: value
			})),
			reason: fixing ? reason.trim() || null : null
		};
		const hash = fingerprint(core);
		if (hash !== lastHash) {
			idempotencyKey = crypto.randomUUID();
			lastHash = hash;
		}

		savingMode = emailReceipt ? 'receipt' : 'save';
		try {
			const result = await onSave({
				...core,
				idempotency_key: idempotencyKey,
				request_hash: hash
			});
			await onSaved(result, emailReceipt);
			onClose();
		} catch (cause) {
			const failure = cause as InvoiceWriteError;
			fieldErrors = failure.fieldErrors ?? {};
			error = fieldErrors.form ?? (Object.keys(fieldErrors).length ? '' : failure.message);
		} finally {
			savingMode = null;
		}
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog
	{open}
	title={fixing ? 'Fix payment' : 'Collect payment'}
	{subtitle}
	size="large"
	icon={cardIcon}
	iconTone="invoice"
	onClose={close}
>
	<div class="collect-payment">
		<div class="collect-payment__form">
			{#if fixing}
				<p class="collect-payment__intro">
					Enter the payment as it really happened. The mistyped one stays in history, marked as
					corrected.
				</p>
			{/if}
			<div class="collect-payment__amount">
				<MoneyInput
					{currencyCode}
					id="collect-payment-amount"
					label="Amount received"
					bind:value={() => amountMinor, setAmount}
					disabled={saving}
					invalid={Boolean(fieldErrors.amount_minor)}
					errorMessage={fieldErrors.amount_minor ?? ''}
				/>
			</div>

			<div class="collect-payment__pair">
				<div class="collect-payment__method">
					<Select
						id="collect-payment-method"
						label="Payment method"
						icon={bankIcon}
						bind:value={method}
						options={INVOICE_PAYMENT_METHOD_OPTIONS}
						disabled={saving}
					/>
				</div>
				<div class="collect-payment__date">
					<CalendarPicker
						id="collect-payment-date"
						label="Payment date"
						value={calendarDateFromString(paymentDate)}
						onchange={(value) => (paymentDate = calendarDateToString(value))}
					/>
				</div>
			</div>

			<Input
				id="collect-payment-reference"
				label="Reference # (optional)"
				bind:value={reference}
				disabled={saving}
				invalid={Boolean(fieldErrors.reference)}
				errorMessage={fieldErrors.reference ?? ''}
			>
				{@html hashIcon}
			</Input>

			<Textarea
				id="collect-payment-note"
				label="Details (optional)"
				placeholder="Anything to remember about this payment"
				rows={4}
				bind:value={note}
				disabled={saving}
			/>

			{#if fixing}
				<Textarea
					id="collect-payment-reason"
					label="Why is it being fixed? (optional)"
					rows={2}
					maxlength={2000}
					bind:value={reason}
					disabled={saving}
				/>
			{/if}

			{#if error}<Banner type="error" icon={errorIcon}>{error}</Banner>{/if}
		</div>

		<section class="collect-payment__panel" aria-labelledby="collect-payment-apply-title">
			<header class="collect-payment__panel-head">
				<IconTile icon={receiptIcon} tone="invoice" size={32} white />
				<h3 id="collect-payment-apply-title">Apply to invoices</h3>
			</header>
			<ul class="collect-payment__rows">
				{#snippet row(id: string, number: number, detail: string, owed: number)}
					{@const rowError = fieldErrors[`applied_${id}`]}
					<li
						class="collect-payment__row"
						class:collect-payment__row--ticked={id in applied}
						class:collect-payment__row--invalid={Boolean(rowError)}
					>
						<div class="collect-payment__row-pick">
							<Checkbox
								id={`collect-payment-pick-${id}`}
								label={`Invoice #${number}`}
								description={`${detail} · owes ${money.format(owed / 100)}`}
								checked={id in applied}
								onchange={(checked) => toggle(id, checked)}
								disabled={saving}
							/>
							{#if rowError}<p class="collect-payment__row-error" role="alert">
									<span aria-hidden="true">{@html errorIcon}</span>{rowError}
								</p>{/if}
						</div>
						{#if id in applied}
							<div class="collect-payment__row-amount">
								<MoneyInput
									{currencyCode}
									id={`collect-payment-amount-${id}`}
									label={`Amount for invoice #${number}`}
									size="small"
									bind:value={() => applied[id] ?? 0, (value) => (applied[id] = value)}
									disabled={saving}
									invalid={Boolean(rowError)}
								/>
							</div>
						{/if}
					</li>
				{/snippet}

				{#each pinned as entry (entry.id)}
					{@render row(entry.id, entry.number, entry.detail, entry.owedMinor)}
				{/each}
				{#if openInvoicesQuery.isPending}
					<li class="collect-payment__row collect-payment__row--bone" aria-hidden="true">
						<span class="collect-payment__bone collect-payment__bone--box"></span>
						<span class="collect-payment__bone-lines">
							<span class="collect-payment__bone collect-payment__bone--title"></span>
							<span class="collect-payment__bone collect-payment__bone--line"></span>
						</span>
					</li>
				{:else}
					{#each otherInvoices as invoice (invoice.id)}
						{@render row(
							invoice.id,
							invoice.invoice_number,
							`Due ${dueFormat.format(new Date(`${invoice.due_date}T00:00:00`))}`,
							invoice.remaining_minor ?? 0
						)}
					{/each}
				{/if}
			</ul>

			<div class="collect-payment__summary">
				<div class="collect-payment__bar" aria-hidden="true">
					{#if appliedShare > 0}<span
							class="collect-payment__bar-applied"
							style:flex-grow={appliedShare}
						></span>{/if}
					{#if creditMinor > 0}<span
							class="collect-payment__bar-credit"
							style:flex-grow={1 - appliedShare}
						></span>{/if}
				</div>
				<p class="collect-payment__line">
					<span class="collect-payment__dot"></span>Applied
					<strong>{money.format(appliedMinor / 100)}</strong>
				</p>
				{#if creditMinor > 0}
					<p class="collect-payment__line collect-payment__line--credit">
						<span class="collect-payment__dot"></span>Kept as client credit
						<strong>{money.format(creditMinor / 100)}</strong>
					</p>
				{/if}
			</div>
		</section>
	</div>

	{#snippet footer()}
		<div class="collect-payment__actions">
			<Button variant="secondary" onclick={close} disabled={saving}>Cancel</Button>
			{#if !fixing}
				<Button
					variant="secondary"
					onclick={() => void submit(true)}
					disabled={savingMode === 'save'}
					loading={savingMode === 'receipt'}
				>
					{@html mailIcon}
					Save and email receipt
				</Button>
			{/if}
			<Button
				variant="primary"
				onclick={() => void submit(false)}
				disabled={savingMode === 'receipt'}
				loading={savingMode === 'save'}
			>
				{@html checkIcon}
				{fixing ? 'Save corrected payment' : 'Collect payment'}
			</Button>
		</div>
	{/snippet}
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.collect-payment {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 400px;
		// The two sides run to the pop-up's edges, so the body's own 20 padding is taken back.
		margin: calc(var(--space-medium) * -1);

		&__form {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			min-width: 0;
			padding: var(--space-medium);
		}

		&__intro {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
		}

		// Amount received: the 56 high money box, its sign in a 48 block, the amount large at the right.
		&__amount {
			:global(.input__control) {
				min-height: 56px;
			}

			:global(input) {
				font-size: var(--typography--fontSize-largest);
				font-weight: 700;
				letter-spacing: -0.4px;
			}

			:global(.money-input__currency) {
				min-width: 48px;
				font-size: var(--typography--fontSize-large);
			}
		}

		&__pair {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base);
		}

		&__method {
			:global(.select__icon) {
				color: var(--color-invoice);
			}

			// The chosen method sits next to its icon, not centred between icon and chevron.
			:global(.select__value) {
				flex: 1 1 auto;
			}
		}

		&__date :global(.calendar-picker__trigger) {
			color: var(--color-time);
		}

		&__panel {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);
			padding: var(--space-medium);
			border-left: var(--border-base) solid var(--color-invoice--surface-edge);
			background: var(--color-invoice--surface);
		}

		&__panel-head {
			display: flex;
			align-items: center;
			gap: var(--space-slim);

			h3 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
				font-weight: 600;
			}
		}

		&__rows {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__row {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-slim) var(--space-slim) var(--space-slim) 14px;
			border: var(--border-base) solid var(--color-invoice--surface-edge);
			border-radius: 12px;
			background: var(--color-surface);

			&--ticked {
				border: 1.5px solid var(--color-invoice);
			}

			&--invalid {
				border: 1.5px solid var(--color-critical);
			}
		}

		&__row-pick {
			flex: 1 1 auto;
			min-width: 0;
		}

		&__row-error {
			display: flex;
			gap: 6px;
			align-items: flex-start;
			margin: var(--space-smaller) 0 0 28px;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;

			span {
				display: inline-flex;
				padding-top: 1px;
			}

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__row-amount {
			flex: 0 0 120px;

			:global(.input__label) {
				position: absolute;
				width: 1px;
				height: 1px;
				overflow: hidden;
				clip-path: inset(50%);
				white-space: nowrap;
			}
		}

		&__bone-lines {
			display: grid;
			gap: 6px;
		}

		&__bone {
			display: block;
			border-radius: var(--radius-small);
			background: var(--color-border);

			&--box {
				width: 18px;
				height: 18px;
			}

			&--title {
				width: 96px;
				height: 12px;
			}

			&--line {
				width: 150px;
				height: 8px;
			}
		}

		&__summary {
			display: grid;
			gap: var(--space-slim);
			padding: 14px;
			border: var(--border-base) solid var(--color-invoice--surface-edge);
			border-radius: 12px;
			background: var(--color-surface);
		}

		&__bar {
			display: flex;
			gap: 3px;
			height: 8px;

			span {
				border-radius: var(--radius-small);
			}
		}

		&__bar-applied {
			background: var(--color-invoice);
		}

		&__bar-credit {
			background: var(--color-client);
		}

		&__line {
			--line-dot: var(--color-invoice);
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-label);
			font-weight: 500;

			strong {
				margin-left: auto;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 700;
			}

			&--credit {
				--line-dot: var(--color-client);
			}
		}

		&__dot {
			width: 8px;
			height: 8px;
			border-radius: var(--radius-circle);
			background: var(--line-dot);
		}

		&__actions {
			display: flex;
			gap: var(--space-small);
			margin-left: auto;
		}
	}
</style>
