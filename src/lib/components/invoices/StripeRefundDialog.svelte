<script lang="ts">
	import { untrack } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import MoneyInput from '$lib/components/forms/MoneyInput.svelte';
	import type { InvoiceWriteError, StripePaymentRefundResult } from '$lib/invoices/api';

	// Online payments Part 5: sending money back through Stripe. Simpler than RefundPaymentDialog on purpose --
	// there is no method, date or reference to pick, because Stripe supplies all three once it confirms the
	// money actually moved. reserve_stripe_payment_refund is the authority on how much is left to refund (it
	// accounts for what is applied to a bill, any earlier refund, and any other refund already waiting on
	// Stripe), so the soft ceiling here is only the payment's face value, same as the manual dialog.
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
			idempotency_key: string;
			request_hash: string;
		}) => Promise<StripePaymentRefundResult>;
		onSaved: (result: StripePaymentRefundResult) => void | Promise<void>;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);

	function fingerprint(value: unknown): string {
		const json = JSON.stringify(value);
		let hash = 0x811c9dc5;
		for (let index = 0; index < json.length; index++) {
			hash ^= json.charCodeAt(index);
			hash = Math.imul(hash, 0x01000193);
		}
		return `v1:${(hash >>> 0).toString(16)}`;
	}

	let refundAmountMinor = $state(untrack(() => amountMinor));
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
			fieldErrors = { amount_minor: 'Enter how much to refund.' };
			return;
		}
		if (refundAmountMinor > amountMinor) {
			fieldErrors = { amount_minor: 'That is more than this payment was ever worth.' };
			return;
		}

		const core = { amount_minor: refundAmountMinor };
		const hash = fingerprint(core);
		if (hash !== lastHash) {
			idempotencyKey = crypto.randomUUID();
			lastHash = hash;
		}

		saving = true;
		try {
			const result = await onSave({ ...core, idempotency_key: idempotencyKey, request_hash: hash });
			await onSaved(result);
			onClose();
		} catch (cause) {
			const failure = cause as InvoiceWriteError;
			fieldErrors = failure.fieldErrors ?? {};
			error = fieldErrors.form ?? (Object.keys(fieldErrors).length ? '' : failure.message);
		} finally {
			saving = false;
		}
	}
</script>

<Dialog {open} title="Refund through Stripe" size="default" onClose={close}>
	<div class="stripe-refund">
		<p class="stripe-refund__intro">
			This sends money back to the customer's card or bank through Stripe. It can take a few days to
			show up on their statement.
		</p>

		<MoneyInput
			id="stripe-refund-amount"
			label="Amount to refund"
			bind:value={refundAmountMinor}
			disabled={saving}
			invalid={Boolean(fieldErrors.amount_minor)}
			errorMessage={fieldErrors.amount_minor ?? ''}
		/>

		{#if error}<p class="stripe-refund__error" role="alert">{error}</p>{/if}

		<footer class="stripe-refund__footer">
			<Button variant="secondary" onclick={close} disabled={saving}>Cancel</Button>
			<Button
				variant="primary"
				variation="destructive"
				onclick={() => void submit()}
				loading={saving}
			>
				Refund {money.format(refundAmountMinor / 100)}
			</Button>
		</footer>
	</div>
</Dialog>

<style lang="scss">
	.stripe-refund {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.stripe-refund__intro {
		margin: 0;
		color: var(--color-text);
	}

	.stripe-refund__error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.stripe-refund__footer {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
		margin-top: var(--space-small);
	}
</style>
