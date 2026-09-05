<script lang="ts">
	import { untrack } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import MoneyInput from '$lib/components/forms/MoneyInput.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import { calendarDateFromString, calendarDateToString } from '$lib/components/ui/date-time';
	import {
		INVOICE_PAYMENT_METHOD_OPTIONS,
		type InvoicePaymentMethod
	} from '$lib/invoices/payment-methods';
	import type { InvoiceWriteError, RecordInvoicePaymentResult } from '$lib/invoices/api';

	// Manual collection against the one open invoice, the same onSave/onSaved shape RecordDiscountCard and
	// RecordTaxCard already use on this page: the dialog owns its fields and validation, the page owns the
	// write's tenant context (client_id) and what happens after (invalidate, toast). Spreading one payment
	// across several of a client's open invoices is a later, deferred screen — this form only ever pays the
	// one bill it was opened from.
	let {
		open,
		invoiceNumber,
		remainingMinor,
		currencyCode,
		locale,
		onClose,
		onSave,
		onSaved
	}: {
		open: boolean;
		invoiceNumber: number;
		remainingMinor: number;
		currencyCode: string;
		locale: string;
		onClose: () => void;
		onSave: (payload: {
			amount_minor: number;
			method: InvoicePaymentMethod;
			payment_date: string;
			reference: string | null;
			note: string | null;
			idempotency_key: string;
			request_hash: string;
		}) => Promise<RecordInvoicePaymentResult>;
		onSaved: () => void | Promise<void>;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
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
	let amountMinor = $state(untrack(() => remainingMinor));
	let method = $state<InvoicePaymentMethod>('other');
	let paymentDate = $state(todayIso());
	let reference = $state('');
	let note = $state('');
	let saving = $state(false);
	let error = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let idempotencyKey = crypto.randomUUID();
	let lastHash = '';

	function close() {
		if (saving) return;
		onClose();
	}

	async function submit() {
		if (saving) return;
		fieldErrors = {};
		error = '';

		if (!amountMinor || amountMinor <= 0) {
			fieldErrors = { amount_minor: 'Enter how much was paid.' };
			return;
		}
		if (amountMinor > remainingMinor) {
			fieldErrors = { amount_minor: `That is more than invoice #${invoiceNumber} still owes.` };
			return;
		}

		const core = {
			amount_minor: amountMinor,
			method,
			payment_date: paymentDate,
			reference: reference.trim() || null,
			note: note.trim() || null
		};
		const hash = fingerprint(core);
		if (hash !== lastHash) {
			idempotencyKey = crypto.randomUUID();
			lastHash = hash;
		}

		saving = true;
		try {
			await onSave({ ...core, idempotency_key: idempotencyKey, request_hash: hash });
			await onSaved();
			onClose();
		} catch (cause) {
			const failure = cause as InvoiceWriteError;
			fieldErrors = failure.fieldErrors ?? {};
			error = Object.keys(fieldErrors).length ? '' : failure.message;
		} finally {
			saving = false;
		}
	}
</script>

<Dialog {open} title="Collect payment" size="default" onClose={close}>
	<div class="collect-payment">
		<p class="collect-payment__balance">
			Invoice #{invoiceNumber} still owes <strong>{money.format(remainingMinor / 100)}</strong>
		</p>

		<MoneyInput
			id="collect-payment-amount"
			label="Amount received"
			bind:value={amountMinor}
			disabled={saving}
			invalid={Boolean(fieldErrors.amount_minor)}
			errorMessage={fieldErrors.amount_minor ?? ''}
		/>

		<Select
			id="collect-payment-method"
			label="Payment method"
			bind:value={method}
			options={INVOICE_PAYMENT_METHOD_OPTIONS}
			disabled={saving}
		/>

		<CalendarPicker
			id="collect-payment-date"
			label="Payment date"
			value={calendarDateFromString(paymentDate)}
			onchange={(value) => (paymentDate = calendarDateToString(value))}
		/>

		<Input
			id="collect-payment-reference"
			label="Reference # (optional)"
			bind:value={reference}
			disabled={saving}
			invalid={Boolean(fieldErrors.reference)}
			errorMessage={fieldErrors.reference ?? ''}
		/>

		<Textarea
			id="collect-payment-note"
			label="Details (optional)"
			rows={3}
			bind:value={note}
			disabled={saving}
		/>

		{#if error}<p class="collect-payment__error" role="alert">{error}</p>{/if}

		<footer class="collect-payment__footer">
			<Button variant="secondary" onclick={close} disabled={saving}>Cancel</Button>
			<Button variant="primary" onclick={() => void submit()} loading={saving}>
				Collect payment
			</Button>
		</footer>
	</div>
</Dialog>

<style lang="scss">
	:global(.collect-payment) {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	:global(.collect-payment__balance) {
		margin: 0;
		color: var(--color-text);
	}

	:global(.collect-payment__balance strong) {
		color: var(--color-heading);
	}

	:global(.collect-payment__error) {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	:global(.collect-payment__footer) {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
		margin-top: var(--space-small);
	}
</style>
