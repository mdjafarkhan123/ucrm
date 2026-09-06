<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';

	// Invoices 5b-4 — Jobber's "Invoice now / Invoice later" prompt, shown right after a visit is marked
	// complete on a job that is priced per visit and set to remind "after each completed visit". Matches the
	// documented Jobber App flow (help.getjobber.com/en/articles/invoices-in-the-jobber-app): Invoice now opens
	// a draft seeded from the job's lines; Invoice later leaves the reminder (the job's ready-to-bill list),
	// which the completion command has already raised. Closing the dialog is the "later" choice.
	let {
		open,
		clientName,
		visitDate,
		amountMinor,
		currencyCode = 'USD',
		locale = 'en-US',
		onInvoiceNow,
		onInvoiceLater
	}: {
		open: boolean;
		clientName: string;
		/** The completed visit's own day (YYYY-MM-DD), or null for an anytime / unscheduled visit. */
		visitDate: string | null;
		/** What one visit's copy of the job's lines comes to. Null when the reader has no price access. */
		amountMinor: number | null;
		currencyCode?: string;
		locale?: string;
		onInvoiceNow: () => void;
		onInvoiceLater: () => void;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	const dateFormat = $derived(
		new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric' })
	);

	const amountLabel = $derived(amountMinor !== null ? money.format(amountMinor / 100) : null);
	const dayLabel = $derived(
		visitDate ? dateFormat.format(new Date(`${visitDate}T12:00:00`)) : null
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog {open} title="Visit completed" size="small" onClose={onInvoiceLater}>
	<div class="visit-invoice-prompt">
		<div class="visit-invoice-prompt__hero">
			<span class="visit-invoice-prompt__hero-icon" aria-hidden="true">{@html receiptIcon}</span>
			{#if amountLabel}
				<p class="visit-invoice-prompt__amount">{amountLabel}</p>
				<p class="visit-invoice-prompt__for">to bill {clientName}</p>
			{:else}
				<p class="visit-invoice-prompt__for">Ready to bill {clientName}</p>
			{/if}
		</div>

		<p class="visit-invoice-prompt__question">
			{#if dayLabel}
				Invoice the visit completed {dayLabel} now, or leave it for later?
			{:else}
				Invoice this visit now, or leave it for later?
			{/if}
		</p>

		<div class="visit-invoice-prompt__actions">
			<Button variant="secondary" variation="subtle" onclick={onInvoiceLater}>Invoice later</Button>
			<Button variant="primary" onclick={onInvoiceNow}>Invoice now</Button>
		</div>

		<p class="visit-invoice-prompt__hint">
			“Later” keeps this visit on the job’s ready-to-bill list.
		</p>
	</div>
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.visit-invoice-prompt {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__hero {
			display: flex;
			flex-direction: column;
			align-items: center;
			gap: var(--space-smallest);
			padding: var(--space-large) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-success--surface);
			color: var(--color-success--onSurface);
			text-align: center;
		}

		&__hero-icon {
			display: flex;
			margin-bottom: var(--space-smaller);

			:global(svg) {
				display: block;
				width: 28px;
				height: 28px;
			}
		}

		&__amount {
			margin: 0;
			font-size: var(--typography--fontSize-largest);
			font-weight: 700;
			line-height: var(--typography--lineHeight-tightest);
			font-variant-numeric: tabular-nums;
		}

		&__for {
			margin: 0;
			font-size: var(--typography--fontSize-small);
		}

		&__question {
			margin: 0;
			color: var(--color-text);
			line-height: var(--typography--lineHeight-large);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
