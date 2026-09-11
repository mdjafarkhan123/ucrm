<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { untrack } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import MoneyInput from '$lib/components/forms/MoneyInput.svelte';
	import {
		clientOpenInvoicesKey,
		fetchClientOpenInvoices,
		type InvoiceWriteError
	} from '$lib/invoices/api';
	import { INVOICE_STATUS_LABELS } from '$lib/invoices/statuses';

	// Paid-launch-trust Part 11: "Move to another invoice" on one row of the payment screen's Applied to list.
	// Off until the dialog is actually open, then cached — the same shape SelectWorkDialog uses for its own
	// picker. move_client_payment resolves the amount itself when it is left at the full allocation (the
	// common case); the field is here so a partial move — some of this money stays where it is — is possible
	// without a second screen.
	let {
		open,
		clientId,
		currentInvoiceId,
		allocation,
		currencyCode,
		locale,
		onClose,
		onSave,
		onSaved
	}: {
		open: boolean;
		clientId: string;
		currentInvoiceId: string;
		allocation: { invoiceNumber: number; amountMinor: number };
		currencyCode: string;
		locale: string;
		onClose: () => void;
		onSave: (
			targetInvoiceId: string,
			amountMinor: number | null,
			reason: string | null,
			idempotencyKey: string,
			requestHash: string
		) => Promise<unknown>;
		onSaved: () => void | Promise<void>;
	} = $props();

	const invoicesQuery = createQuery(() => ({
		queryKey: clientOpenInvoicesKey(clientId),
		queryFn: () => fetchClientOpenInvoices(clientId, currentInvoiceId),
		enabled: open && Boolean(clientId),
		staleTime: 15_000
	}));

	const invoiceOptions = $derived(
		(invoicesQuery.data ?? []).map((invoice) => ({
			value: invoice.id,
			label: `Invoice #${invoice.invoice_number} · ${INVOICE_STATUS_LABELS[invoice.derived_status]}`
		}))
	);

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);

	let targetInvoiceId = $state('');
	let amountMinor = $state(untrack(() => allocation.amountMinor));
	let reason = $state('');
	let saving = $state(false);
	let error = $state('');
	let fieldErrors = $state<Record<string, string>>({});
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

	function close() {
		if (saving) return;
		onClose();
	}

	async function confirm() {
		if (saving) return;
		fieldErrors = {};
		error = '';

		if (!targetInvoiceId) {
			fieldErrors = { target_invoice_id: 'Choose an invoice to move this payment to.' };
			return;
		}
		if (!amountMinor || amountMinor <= 0) {
			fieldErrors = { amount_minor: 'Enter how much to move.' };
			return;
		}
		if (amountMinor > allocation.amountMinor) {
			fieldErrors = {
				amount_minor: `That is more than the ${money.format(
					allocation.amountMinor / 100
				)} on invoice #${allocation.invoiceNumber}.`
			};
			return;
		}

		// The whole allocation moving is the common case; sending null (rather than repeating the full amount)
		// lets move_client_payment's own default speak for it and keeps a full move and a "typed the full
		// number back" move indistinguishable to the command.
		const movingEverything = amountMinor === allocation.amountMinor;
		const trimmedReason = reason.trim() || null;
		const core = {
			target_invoice_id: targetInvoiceId,
			amount_minor: movingEverything ? null : amountMinor,
			reason: trimmedReason
		};
		const hash = fingerprint(core);
		if (hash !== lastHash) {
			idempotencyKey = crypto.randomUUID();
			lastHash = hash;
		}

		saving = true;
		try {
			await onSave(targetInvoiceId, core.amount_minor, trimmedReason, idempotencyKey, hash);
			await onSaved();
			onClose();
		} catch (cause) {
			const failure = cause as InvoiceWriteError;
			fieldErrors = failure.fieldErrors ?? {};
			// A database refusal (a currency mismatch, or moving more than the allocation holds) arrives as a
			// form-level field error rather than one tied to a specific input.
			error = fieldErrors.form ?? (Object.keys(fieldErrors).length ? '' : failure.message);
		} finally {
			saving = false;
		}
	}
</script>

<Dialog {open} title="Move to another invoice" size="default" onClose={close}>
	<div class="move-payment">
		<p class="move-payment__intro">
			Moving money off invoice #{allocation.invoiceNumber}. Up to {money.format(
				allocation.amountMinor / 100
			)} available.
		</p>

		{#if invoicesQuery.isPending}
			<p class="move-payment__loading">Loading this client's other invoices…</p>
		{:else if invoicesQuery.isError}
			<p class="move-payment__error" role="alert">
				Those invoices could not be loaded. Close this and try again.
			</p>
		{:else if invoiceOptions.length === 0}
			<p class="move-payment__loading">This client has no other open invoice to move money to.</p>
		{:else}
			<Select
				id="move-payment-invoice"
				label="Move to"
				bind:value={targetInvoiceId}
				options={invoiceOptions}
				disabled={saving}
			/>
			{#if fieldErrors.target_invoice_id}
				<p class="move-payment__error" role="alert">{fieldErrors.target_invoice_id}</p>
			{/if}

			<MoneyInput
				id="move-payment-amount"
				label="Amount to move"
				bind:value={amountMinor}
				disabled={saving}
				invalid={Boolean(fieldErrors.amount_minor)}
				errorMessage={fieldErrors.amount_minor ?? ''}
			/>

			<Textarea
				id="move-payment-reason"
				label="Reason (optional)"
				rows={3}
				maxlength={2000}
				bind:value={reason}
				disabled={saving}
			/>
		{/if}

		{#if error}<p class="move-payment__error" role="alert">{error}</p>{/if}

		<footer class="move-payment__footer">
			<Button variant="secondary" onclick={close} disabled={saving}>Cancel</Button>
			<Button
				variant="primary"
				onclick={() => void confirm()}
				loading={saving}
				disabled={invoiceOptions.length === 0}
			>
				Move payment
			</Button>
		</footer>
	</div>
</Dialog>

<style lang="scss">
	.move-payment {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.move-payment__intro,
	.move-payment__loading {
		margin: 0;
		color: var(--color-text);
	}

	.move-payment__error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.move-payment__footer {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
		margin-top: var(--space-small);
	}
</style>
