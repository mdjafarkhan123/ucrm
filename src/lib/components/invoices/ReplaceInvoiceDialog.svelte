<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import type { InvoiceWriteError } from '$lib/invoices/api';

	// The confirm step of a correction or rebill (D6). It shows exactly what changes for the client — the old
	// and new totals, the difference, what they already paid moving across, and what is left to pay — then
	// issues the draft in place of the original, by email or marked as sent. The difference shown is the one
	// sent back to the database, which refuses it if the numbers moved in the meantime.
	let {
		open,
		kind,
		original,
		loadError = false,
		newTotalMinor,
		currencyCode,
		locale,
		clientEmail,
		onClose,
		onConfirm
	}: {
		open: boolean;
		/** 'correction' replaces a live bill; 'rebill' re-bills a voided one, which carries no payments. */
		kind: 'correction' | 'rebill';
		/** The bill being replaced; null while it loads. `paidMinor` is the money still applied to it, which
		 *  moves across. */
		original: { number: number; totalMinor: number; paidMinor: number } | null;
		loadError?: boolean;
		newTotalMinor: number;
		currencyCode: string;
		locale: string;
		/** Null hides "Send to client". */
		clientEmail: string | null;
		onClose: () => void;
		onConfirm: (method: 'sent' | 'marked_sent', differenceMinor: number) => Promise<void>;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	const format = (minor: number) => money.format(minor / 100);

	const differenceMinor = $derived(newTotalMinor - (original?.totalMinor ?? 0));
	const carriedMinor = $derived(Math.min(original?.paidMinor ?? 0, newTotalMinor));
	const leftMinor = $derived(newTotalMinor - carriedMinor);
	const creditMinor = $derived((original?.paidMinor ?? 0) - carriedMinor);
	const title = $derived(original ? `Replace invoice #${original.number}?` : 'Replace invoice?');

	let saving = $state<'sent' | 'marked_sent' | null>(null);
	let error = $state('');

	function close() {
		if (saving) return;
		onClose();
	}

	async function confirm(method: 'sent' | 'marked_sent') {
		if (saving || !original) return;
		error = '';
		saving = method;
		try {
			await onConfirm(method, differenceMinor);
			onClose();
		} catch (cause) {
			const failure = cause as InvoiceWriteError;
			error = failure.fieldErrors?.form ?? failure.message ?? 'That invoice could not be replaced.';
		} finally {
			saving = null;
		}
	}
</script>

<Dialog {open} {title} size="default" onClose={close}>
	<div class="replace-invoice">
		{#if !original}
			{#if loadError}
				<p class="replace-invoice__error" role="alert">
					The original invoice could not be loaded. Close this and try again.
				</p>
			{:else}
				<div
					class="replace-invoice__figures"
					aria-busy="true"
					aria-label="Loading the original invoice"
				>
					<span class="skeleton skeleton--text"></span>
					<span class="skeleton skeleton--text skeleton--text-short"></span>
				</div>
			{/if}
		{:else}
			<p class="replace-invoice__intro">
				{kind === 'rebill'
					? `This invoice becomes the bill in place of voided invoice #${original.number}.`
					: `This invoice becomes the bill the client owes. Invoice #${original.number} stays on record, marked as replaced.`}
			</p>

			<dl class="replace-invoice__figures">
				<div class="replace-invoice__row">
					<dt>Invoice #{original.number}</dt>
					<dd>{format(original.totalMinor)}</dd>
				</div>
				<div class="replace-invoice__row">
					<dt>This invoice</dt>
					<dd>{format(newTotalMinor)}</dd>
				</div>
				<div class="replace-invoice__row replace-invoice__row--muted">
					<dt>Difference</dt>
					<dd>{differenceMinor > 0 ? '+' : ''}{format(differenceMinor)}</dd>
				</div>
				{#if carriedMinor > 0}
					<div class="replace-invoice__row">
						<dt>Already paid, moves across</dt>
						<dd>−{format(carriedMinor)}</dd>
					</div>
				{/if}
				<div class="replace-invoice__row replace-invoice__row--total">
					<dt>Left to pay</dt>
					<dd>{format(leftMinor)}</dd>
				</div>
			</dl>

			{#if creditMinor > 0}
				<p class="replace-invoice__note">
					The client paid {format(creditMinor)} more than this invoice. That stays on their account as
					credit.
				</p>
			{/if}
		{/if}

		{#if error}<p class="replace-invoice__error" role="alert">{error}</p>{/if}

		<footer class="replace-invoice__footer">
			<Button variant="secondary" onclick={close} disabled={Boolean(saving)}>Cancel</Button>
			<Button
				variant={clientEmail ? 'secondary' : 'primary'}
				onclick={() => void confirm('marked_sent')}
				disabled={!original || saving === 'sent'}
				loading={saving === 'marked_sent'}
			>
				Replace and mark as sent
			</Button>
			{#if clientEmail}
				<Button
					variant="primary"
					onclick={() => void confirm('sent')}
					disabled={!original || saving === 'marked_sent'}
					loading={saving === 'sent'}
				>
					Replace and email client
				</Button>
			{/if}
		</footer>
	</div>
</Dialog>

<style lang="scss">
	.replace-invoice {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.replace-invoice__intro,
	.replace-invoice__note {
		margin: 0;
		color: var(--color-text--secondary);
	}

	.replace-invoice__figures {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		margin: 0;
		padding: var(--space-small) var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}

	.replace-invoice__row {
		display: flex;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-smaller) 0;

		dt,
		dd {
			margin: 0;
		}

		dd {
			font-variant-numeric: tabular-nums;
			white-space: nowrap;
		}
	}

	.replace-invoice__row--muted {
		color: var(--color-text--secondary);
	}

	.replace-invoice__row--total {
		margin-top: var(--space-smaller);
		padding-top: var(--space-small);
		border-top: var(--border-base) solid var(--color-border);
		color: var(--color-heading);
		font-weight: 600;
	}

	.replace-invoice__error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.replace-invoice__footer {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
		margin-top: var(--space-small);
	}
</style>
