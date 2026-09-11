<script lang="ts">
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import type { InvoiceWriteError } from '$lib/invoices/api';
	import arrowBackIcon from '@tabler/icons/outline/arrow-back-up.svg?raw';

	// Paid-launch-trust Part 11: "Take off this invoice" on one row of the payment screen's Applied to list.
	// unapply_client_payment returns the money to client credit; the entry it reverses stays exactly as it
	// was, which is why this asks for a reason rather than a confirmation of loss — nothing here is destroyed.
	let {
		open,
		invoiceNumber,
		amountMinor,
		currencyCode,
		locale,
		onClose,
		onSave,
		onSaved
	}: {
		open: boolean;
		invoiceNumber: number;
		amountMinor: number;
		currencyCode: string;
		locale: string;
		onClose: () => void;
		onSave: (
			reason: string | null,
			idempotencyKey: string,
			requestHash: string
		) => Promise<unknown>;
		onSaved: () => void | Promise<void>;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);

	// A fresh instance every time the page opens this dialog (it is `{#if}`-gated), so a plain initialiser is
	// the reset — the same shape InvoiceLifecycleDialog relies on.
	let reason = $state('');
	let saving = $state(false);
	let error = $state('');
	let idempotencyKey = crypto.randomUUID();
	let lastHash = '';

	function fingerprint(value: unknown): string {
		const json = JSON.stringify(value);
		let hash = 0x811c9dc5;
		for (let index = 0; index < json.length; index++) {
			hash ^= json.charCodeAt(index);
			hash = Math.imul(hash, 0x01000193);
		}
		return `v1:${(hash >>> 0).toString(16)}`;
	}

	async function confirm() {
		if (saving) return;
		error = '';

		const trimmed = reason.trim() || null;
		const hash = fingerprint({ allocation: 'unapply', reason: trimmed });
		if (hash !== lastHash) {
			idempotencyKey = crypto.randomUUID();
			lastHash = hash;
		}

		saving = true;
		try {
			await onSave(trimmed, idempotencyKey, hash);
			await onSaved();
			onClose();
		} catch (cause) {
			const failure = cause as InvoiceWriteError;
			error = failure.fieldErrors?.form ?? failure.message ?? 'That change could not be saved.';
		} finally {
			saving = false;
		}
	}
</script>

<ConfirmDialog
	{open}
	title="Take this payment off invoice #{invoiceNumber}?"
	icon={arrowBackIcon}
	confirmLabel="Take off invoice"
	loading={saving}
	confirmDisabled={saving}
	onConfirm={() => void confirm()}
	{onClose}
>
	<div class="unapply-payment">
		<p class="unapply-payment__intro">
			{money.format(amountMinor / 100)} goes back to the client's available credit. The original entry
			stays on record.
		</p>

		<Textarea
			id="unapply-payment-reason"
			label="Reason (optional)"
			rows={3}
			maxlength={2000}
			bind:value={reason}
			disabled={saving}
		/>

		{#if error}<p class="unapply-payment__error" role="alert">{error}</p>{/if}
	</div>
</ConfirmDialog>

<style lang="scss">
	.unapply-payment {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.unapply-payment__intro {
		margin: 0;
	}

	.unapply-payment__error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
</style>
