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
	import type { InvoiceWriteError, RefundPaymentResult } from '$lib/invoices/api';

	// Paid-launch-trust Part 11: sending money back on this recorded payment. Same field shape as
	// CollectPaymentDialog — amount, method, date, reference, note — because a refund is the same manual
	// acknowledgement in reverse: it records that money already moved somewhere else, never processes one.
	// refund_client_payment is the authority on how much is actually left to refund (it accounts for what is
	// still applied to a bill and any earlier refund); the soft ceiling here is only the payment's face value,
	// so the database's own message is what a person sees if less than that remains.
	let {
		open,
		amountMinor,
		currencyCode,
		locale,
		onClose,
		onSave,
		onSaved
	}: {
		open: boolean;
		amountMinor: number;
		currencyCode: string;
		locale: string;
		onClose: () => void;
		onSave: (payload: {
			amount_minor: number;
			method: InvoicePaymentMethod;
			refund_date: string;
			reference: string | null;
			note: string | null;
			idempotency_key: string;
			request_hash: string;
		}) => Promise<RefundPaymentResult>;
		onSaved: (result: RefundPaymentResult) => void | Promise<void>;
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

	function fingerprint(value: unknown): string {
		const json = JSON.stringify(value);
		let hash = 0x811c9dc5;
		for (let index = 0; index < json.length; index++) {
			hash ^= json.charCodeAt(index);
			hash = Math.imul(hash, 0x01000193);
		}
		return `v1:${(hash >>> 0).toString(16)}`;
	}

	// A fresh instance every time the page opens this dialog (it is `{#if}`-gated), so plain initialisers are
	// the reset — the same shape CollectPaymentDialog relies on.
	let refundAmountMinor = $state(untrack(() => amountMinor));
	let method = $state<InvoicePaymentMethod>('other');
	let refundDate = $state(todayIso());
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

		if (!refundAmountMinor || refundAmountMinor <= 0) {
			fieldErrors = { amount_minor: 'Enter how much was refunded.' };
			return;
		}
		if (refundAmountMinor > amountMinor) {
			fieldErrors = { amount_minor: 'That is more than this payment was ever worth.' };
			return;
		}

		const core = {
			amount_minor: refundAmountMinor,
			method,
			refund_date: refundDate,
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
			const result = await onSave({
				...core,
				idempotency_key: idempotencyKey,
				request_hash: hash
			});
			await onSaved(result);
			onClose();
		} catch (cause) {
			const failure = cause as InvoiceWriteError;
			fieldErrors = failure.fieldErrors ?? {};
			// A database refusal (the real available-to-refund cap, checked server-side) arrives as a
			// form-level field error rather than one tied to a specific input, so it needs its own fallback —
			// same shape InvoiceLifecycleDialog uses for the database's own guard refusals.
			error = fieldErrors.form ?? (Object.keys(fieldErrors).length ? '' : failure.message);
		} finally {
			saving = false;
		}
	}
</script>

<Dialog {open} title="Refund payment" size="default" onClose={close}>
	<div class="refund-payment">
		<p class="refund-payment__balance">
			This payment was <strong>{money.format(amountMinor / 100)}</strong>. If part of it is still
			applied to a bill or already refunded, take it off first.
		</p>

		<MoneyInput
			id="refund-payment-amount"
			label="Amount refunded"
			bind:value={refundAmountMinor}
			disabled={saving}
			invalid={Boolean(fieldErrors.amount_minor)}
			errorMessage={fieldErrors.amount_minor ?? ''}
		/>

		<Select
			id="refund-payment-method"
			label="Refund method"
			bind:value={method}
			options={INVOICE_PAYMENT_METHOD_OPTIONS}
			disabled={saving}
		/>

		<CalendarPicker
			id="refund-payment-date"
			label="Refund date"
			value={calendarDateFromString(refundDate)}
			onchange={(value) => (refundDate = calendarDateToString(value))}
		/>

		<Input
			id="refund-payment-reference"
			label="Reference # (optional)"
			bind:value={reference}
			disabled={saving}
			invalid={Boolean(fieldErrors.reference)}
			errorMessage={fieldErrors.reference ?? ''}
		/>

		<Textarea
			id="refund-payment-note"
			label="Details (optional)"
			rows={3}
			bind:value={note}
			disabled={saving}
		/>

		{#if error}<p class="refund-payment__error" role="alert">{error}</p>{/if}

		<footer class="refund-payment__footer">
			<Button variant="secondary" onclick={close} disabled={saving}>Cancel</Button>
			<Button
				variant="primary"
				variation="destructive"
				onclick={() => void submit()}
				loading={saving}
			>
				Refund payment
			</Button>
		</footer>
	</div>
</Dialog>

<style lang="scss">
	.refund-payment {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.refund-payment__balance {
		margin: 0;
		color: var(--color-text);
	}

	.refund-payment__balance strong {
		color: var(--color-heading);
	}

	.refund-payment__error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.refund-payment__footer {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
		margin-top: var(--space-small);
	}
</style>
