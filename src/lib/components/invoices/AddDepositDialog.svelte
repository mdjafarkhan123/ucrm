<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import MoneyInput from '$lib/components/forms/MoneyInput.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		fetchInvoiceCredit,
		invoiceCreditKey,
		type ApplyInvoiceCreditInput,
		type InvoiceCreditSource,
		type InvoiceWriteError
	} from '$lib/invoices/api';
	import { INVOICE_PAYMENT_METHOD_LABELS } from '$lib/invoices/payment-methods';

	// "Add deposit" on one invoice, like Jobber's Deposits row: the money this invoice's client has already
	// given -- a recorded payment or a deposit paid on a quote -- that still has some left, put on this bill.
	// Cached by client, and prefetched by the page when the button is hovered, so it usually opens already
	// filled. apply_client_payment does the real checking (same client and currency, what the money has left,
	// what the bill still owes); the amount cap here only saves a round trip.
	let {
		open,
		invoiceId,
		invoiceNumber,
		clientId,
		remainingMinor,
		currencyCode,
		locale,
		onClose,
		onSave,
		onSaved
	}: {
		open: boolean;
		invoiceId: string;
		invoiceNumber: number;
		clientId: string;
		remainingMinor: number;
		currencyCode: string;
		locale: string;
		onClose: () => void;
		onSave: (input: ApplyInvoiceCreditInput) => Promise<unknown>;
		onSaved: () => void | Promise<void>;
	} = $props();

	const creditQuery = createQuery(() => ({
		queryKey: invoiceCreditKey(clientId),
		queryFn: () => fetchInvoiceCredit(invoiceId, clientId),
		enabled: open && Boolean(clientId),
		staleTime: 15_000
	}));

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	const dayFormat = $derived(new Intl.DateTimeFormat(locale, { dateStyle: 'medium' }));

	// Only money in this invoice's own currency can be applied to it; the command refuses the rest anyway.
	const sources = $derived(
		(creditQuery.data ?? []).filter((source) => source.currency_code === currencyCode)
	);

	function describe(source: InvoiceCreditSource) {
		const left = money.format(source.available_minor / 100);
		if (source.source === 'deposit')
			return `Deposit on quote #${source.quote_number} · ${left} left`;
		const method = source.method ? INVOICE_PAYMENT_METHOD_LABELS[source.method] : 'Payment';
		return `${method} · ${dayFormat.format(new Date(source.received_at))} · ${left} left`;
	}

	const options = $derived(
		sources.map((source) => ({ value: source.source_id, label: describe(source) }))
	);

	// Chosen by the person, or the oldest money when they have not chosen -- one source is the common case, so
	// the dialog opens ready to confirm.
	let chosenId = $state('');
	const selected = $derived(sources.find((source) => source.source_id === chosenId) ?? sources[0]);

	// As much as can go on: the money's own remainder or what the bill still owes, whichever is less. It is
	// re-worked whenever the choice changes and the person can type over it until then.
	let amountMinor = $derived(selected ? Math.min(selected.available_minor, remainingMinor) : 0);

	let saving = $state(false);
	let error = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let idempotencyKey = crypto.randomUUID();
	let lastHash = '';

	// The same FNV-1a fingerprint every invoice write uses, so a retry of the exact same application replays
	// instead of applying the money twice.
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
		if (saving || !selected) return;
		fieldErrors = {};
		error = '';

		if (!amountMinor || amountMinor <= 0) {
			fieldErrors = { amount_minor: 'Enter how much to apply.' };
			return;
		}
		if (amountMinor > selected.available_minor) {
			fieldErrors = {
				amount_minor: `Only ${money.format(selected.available_minor / 100)} is left on that money.`
			};
			return;
		}
		if (amountMinor > remainingMinor) {
			fieldErrors = { amount_minor: `That is more than invoice #${invoiceNumber} still owes.` };
			return;
		}

		const core = {
			source: selected.source,
			source_id: selected.source_id,
			amount_minor: amountMinor
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
			error = fieldErrors.form ?? (Object.keys(fieldErrors).length ? '' : failure.message);
		} finally {
			saving = false;
		}
	}
</script>

<Dialog {open} title="Add deposit" size="default" onClose={close}>
	<div class="add-deposit">
		<p class="add-deposit__intro">
			Invoice #{invoiceNumber} still owes <strong>{money.format(remainingMinor / 100)}</strong>.
			Choose money this client has already paid.
		</p>

		{#if creditQuery.isPending}
			<LoadingSkeleton variant="text" label="Loading this client's credit" rows={2} />
		{:else if creditQuery.isError}
			<p class="add-deposit__error" role="alert">
				This client's credit could not be loaded. Close this and try again.
			</p>
		{:else if sources.length === 0}
			<p class="add-deposit__empty">This client has no unused deposit or payment to add.</p>
		{:else}
			<Select
				id="add-deposit-source"
				label="Money to use"
				value={selected?.source_id ?? ''}
				onchange={(id) => (chosenId = id)}
				{options}
				disabled={saving}
			/>

			<MoneyInput
				id="add-deposit-amount"
				label="Amount to add"
				bind:value={amountMinor}
				disabled={saving}
				invalid={Boolean(fieldErrors.amount_minor)}
				errorMessage={fieldErrors.amount_minor ?? ''}
			/>
		{/if}

		{#if error}<p class="add-deposit__error" role="alert">{error}</p>{/if}

		<footer class="add-deposit__footer">
			<Button variant="secondary" onclick={close} disabled={saving}>Cancel</Button>
			<Button
				variant="primary"
				onclick={() => void confirm()}
				loading={saving}
				disabled={!selected}
			>
				Add deposit
			</Button>
		</footer>
	</div>
</Dialog>

<style lang="scss">
	.add-deposit {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.add-deposit__intro,
	.add-deposit__empty {
		margin: 0;
		color: var(--color-text);
	}

	.add-deposit__intro strong {
		color: var(--color-heading);
	}

	.add-deposit__error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.add-deposit__footer {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
		margin-top: var(--space-small);
	}
</style>
