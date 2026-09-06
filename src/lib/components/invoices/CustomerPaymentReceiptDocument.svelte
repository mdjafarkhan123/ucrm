<script lang="ts">
	import type { Snippet } from 'svelte';
	import type { CustomerPaymentReceipt } from '$lib/invoices/customer-receipt';
	import { INVOICE_PAYMENT_METHOD_LABELS } from '$lib/invoices/payment-methods';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';

	// The customer's receipt for one recorded payment, and the only drawing of it there is. The token page
	// hands it a document resolved from a link; the payment detail screen's Print will hand it the same
	// document read straight from the database. Neither one filters anything here — whatever is missing from
	// `doc` was withheld before it left the database.
	//
	// The field set is Jobber's own receipt, exactly: business, transaction-date badge, recipient name and
	// billing address, "Payment receipt", the amount, the three transaction facts, the details note. No
	// receipt number, no invoice number, no line items, no balance. The look is a 1:1 build of
	// Design/invoices/customer-payment-receipt-mockup.html on real UCRM tokens, sharing the invoice
	// document's paper shell so a bill and its receipt read as one office's paperwork.
	let {
		doc,
		notice
	}: {
		doc: CustomerPaymentReceipt;
		/** A strip above the document, for anything staff need told that the customer must never see. */
		notice?: Snippet;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat('en-US', { style: 'currency', currency: doc.receipt.currency_code })
	);
	const longDate = new Intl.DateTimeFormat('en-US', { dateStyle: 'medium' });

	function formatDate(value: string | null) {
		// A `date` column arrives as `YYYY-MM-DD`; `new Date` on that reads it as UTC midnight and shifts the
		// day back one in negative-offset timezones. `T00:00` parses it as local midnight so the date is kept.
		return value ? longDate.format(new Date(`${value}T00:00`)) : null;
	}

	const amount = $derived(money.format(doc.receipt.amount_minor / 100));
	const transactionDate = $derived(formatDate(doc.receipt.transaction_date));

	// The customer sees the same method wording the office picked in Collect payment. An unknown value falls
	// back to itself rather than disappearing — a receipt must never be silent about how money moved.
	const methodLabel = $derived(
		INVOICE_PAYMENT_METHOD_LABELS[
			doc.receipt.method as keyof typeof INVOICE_PAYMENT_METHOD_LABELS
		] ?? doc.receipt.method
	);

	// Two capital letters from the business name, for the corner mark — the same first-and-last-initial rule
	// the invoice document uses.
	const brandInitials = $derived.by(() => {
		const name = (doc.business.name ?? '').trim();
		if (!name) return '—';
		const words = name.split(/\s+/).filter(Boolean);
		if (words.length === 1) return words[0].slice(0, 2).toUpperCase();
		return (words[0][0] + words[words.length - 1][0]).toUpperCase();
	});

	const recipientName = $derived(
		doc.recipient.company_name?.trim() || doc.recipient.display_name || 'Customer'
	);

	const addressLines = $derived.by(() => {
		const address = doc.recipient.address;
		if (!address) return [];
		return [
			address.address_line1,
			address.address_line2,
			[address.city, address.state_region, address.postal_code].filter(Boolean).join(', '),
			address.country
		].filter((line): line is string => Boolean(line && line.trim()));
	});
</script>

<div class="customer-receipt">
	{#if notice}
		<div class="customer-receipt__notice">{@render notice()}</div>
	{/if}

	<article class="customer-receipt__doc">
		<div class="customer-receipt__brandbar"></div>

		<header class="customer-receipt__head">
			<div class="customer-receipt__brand">
				<div class="customer-receipt__brand-mark" aria-hidden="true">{brandInitials}</div>
				<div class="customer-receipt__brand-name">
					{doc.business.name ?? 'Your contractor'}
				</div>
			</div>
			{#if transactionDate}
				<span class="customer-receipt__datebadge">
					Transaction date <b>{transactionDate}</b>
				</span>
			{/if}
		</header>

		<section class="customer-receipt__recipient">
			<h2 class="customer-receipt__recipient-label">Recipient</h2>
			<p class="customer-receipt__recipient-name">{recipientName}</p>
			{#each addressLines as line (line)}
				<p class="customer-receipt__recipient-line">{line}</p>
			{/each}
		</section>

		<section class="customer-receipt__hero">
			<div>
				<h1 class="customer-receipt__title">Payment receipt</h1>
				<p class="customer-receipt__note">
					Thank you — this payment has been received and applied to your account.
				</p>
			</div>
			<div class="customer-receipt__paid">
				<!-- eslint-disable svelte/no-at-html-tags -- a Tabler icon imported at build time, never user input -->
				<div class="customer-receipt__paid-label">
					<span class="customer-receipt__paid-check" aria-hidden="true">{@html checkIcon}</span>
					Paid
				</div>
				<!-- eslint-enable svelte/no-at-html-tags -->
				<div class="customer-receipt__paid-amount">{amount}</div>
			</div>
		</section>

		<dl class="customer-receipt__facts">
			{#if transactionDate}
				<div class="customer-receipt__fact">
					<dt>Transaction date</dt>
					<dd>{transactionDate}</dd>
				</div>
			{/if}
			<div class="customer-receipt__fact">
				<dt>Method of payment</dt>
				<dd>{methodLabel}</dd>
			</div>
			{#if doc.receipt.reference}
				<div class="customer-receipt__fact">
					<dt>Reference number</dt>
					<dd>{doc.receipt.reference}</dd>
				</div>
			{/if}
		</dl>

		{#if doc.receipt.details}
			<section class="customer-receipt__details">
				<h3>Details</h3>
				<p>{doc.receipt.details}</p>
			</section>
		{/if}
	</article>
</div>

<style lang="scss">
	.customer-receipt {
		min-height: 100vh;
		background: var(--color-surface--background);
		color: var(--color-text);
		font-family: var(--typography--fontFamily-normal);
		padding-bottom: var(--space-largest);
	}

	.customer-receipt__notice {
		max-width: 820px;
		margin: var(--space-large) auto 0;
		padding: 0 var(--space-large);
	}

	.customer-receipt__doc {
		max-width: 820px;
		margin: var(--space-large) auto var(--space-extravagant);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		box-shadow: var(--shadow-high);
		overflow: hidden;
	}

	// The same branded band the invoice document wears, so a bill and its receipt match.
	.customer-receipt__brandbar {
		height: 5px;
		background: linear-gradient(
			90deg,
			var(--color-invoice) 0%,
			var(--color-informative) 55%,
			var(--color-brand) 100%
		);
	}

	.customer-receipt__head {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: var(--space-large);
		padding: var(--space-larger) var(--space-largest) var(--space-large);
	}

	.customer-receipt__brand {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
	}

	.customer-receipt__brand-mark {
		width: 46px;
		height: 46px;
		border-radius: var(--radius-slim, 12px);
		display: grid;
		place-items: center;
		background: var(--color-surface--reverse);
		color: var(--color-text--reverse);
		font-family: var(--typography--fontFamily-display);
		font-weight: 800;
		font-size: var(--typography--fontSize-larger);
		letter-spacing: 0.02em;
	}

	.customer-receipt__brand-name {
		font-family: var(--typography--fontFamily-display);
		font-weight: 700;
		font-size: var(--typography--fontSize-larger);
		color: var(--color-heading);
		line-height: var(--typography--lineHeight-minuscule);
	}

	// The dark filled badge Jobber puts in this slot on both the invoice and the receipt.
	.customer-receipt__datebadge {
		display: inline-flex;
		align-items: baseline;
		gap: var(--space-smaller);
		padding: var(--space-small) var(--space-base);
		border-radius: 999px;
		background: var(--color-surface--reverse);
		color: var(--color-text--reverse);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
		white-space: nowrap;

		b {
			font-weight: 700;
			font-variant-numeric: tabular-nums;
		}
	}

	// Name and billing address only. No email, no phone: a receipt is a record of money, not a contact card.
	.customer-receipt__recipient {
		margin: 0 var(--space-largest);
		padding: var(--space-smaller) 0 var(--space-large);
		border-bottom: 1px solid var(--color-border);
	}

	.customer-receipt__recipient-label {
		margin: 0 0 var(--space-smaller);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		letter-spacing: 0.14em;
		text-transform: uppercase;
		color: var(--color-text--secondary);
	}

	.customer-receipt__recipient-name {
		margin: 0;
		font-weight: 600;
		font-size: var(--typography--fontSize-base);
		color: var(--color-heading);
	}

	.customer-receipt__recipient-line {
		margin: 2px 0 0;
		font-size: var(--typography--fontSize-base);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}

	.customer-receipt__hero {
		display: grid;
		grid-template-columns: 1fr auto;
		gap: var(--space-larger);
		align-items: center;
		padding: var(--space-larger) var(--space-largest) var(--space-large);
	}

	.customer-receipt__title {
		margin: 0;
		font-family: var(--typography--fontFamily-display);
		font-weight: 600;
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-base);
		color: var(--color-heading);
	}

	.customer-receipt__note {
		margin: var(--space-small) 0 0;
		font-size: var(--typography--fontSize-base);
		color: var(--color-text--secondary);
		max-width: 34ch;
	}

	// The one number that matters, and the only place on the document wearing a colour.
	.customer-receipt__paid {
		text-align: right;
		padding: var(--space-base) var(--space-large);
		border-radius: var(--radius-large);
		background: var(--color-success--surface);
		border: 1px solid var(--color-success);
		min-width: 220px;
	}

	.customer-receipt__paid-label {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;
		letter-spacing: 0.14em;
		text-transform: uppercase;
		color: var(--color-success--onSurface);
	}

	.customer-receipt__paid-check {
		display: inline-flex;
		width: 15px;
		height: 15px;

		:global(svg) {
			width: 100%;
			height: 100%;
			stroke: currentcolor;
			stroke-width: 3;
			fill: none;
		}
	}

	.customer-receipt__paid-amount {
		font-family: var(--typography--fontFamily-display);
		font-weight: 800;
		font-size: var(--typography--fontSize-jumbo);
		line-height: var(--typography--lineHeight-minuscule);
		color: var(--color-success--onSurface);
		font-variant-numeric: tabular-nums;
		margin-top: var(--space-smaller);
	}

	// The transaction facts, in Jobber's order and wording.
	.customer-receipt__facts {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: var(--space-large);
		margin: 0 var(--space-largest);
		padding: 0 0 var(--space-larger);
	}

	.customer-receipt__fact {
		dt {
			margin: 0 0 var(--space-smallest, 4px);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			letter-spacing: 0.1em;
			text-transform: uppercase;
			color: var(--color-text--secondary);
		}

		dd {
			margin: 0;
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			color: var(--color-heading);
			overflow-wrap: anywhere;
		}
	}

	// The free-text note, verbatim, under its own divider.
	.customer-receipt__details {
		margin: 0 var(--space-largest);
		padding: var(--space-large) 0 var(--space-largest);
		border-top: 1px solid var(--color-border);

		h3 {
			margin: 0 0 var(--space-smaller);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			letter-spacing: 0.1em;
			text-transform: uppercase;
			color: var(--color-text--secondary);
		}

		p {
			margin: 0;
			font-size: var(--typography--fontSize-base);
			color: var(--color-text--secondary);
			line-height: var(--typography--lineHeight-larger);
			max-width: 62ch;
			white-space: pre-wrap;
		}
	}

	@media (max-width: 720px) {
		.customer-receipt__head,
		.customer-receipt__hero {
			padding-left: var(--space-large);
			padding-right: var(--space-large);
		}

		.customer-receipt__recipient,
		.customer-receipt__facts,
		.customer-receipt__details {
			margin-left: var(--space-large);
			margin-right: var(--space-large);
		}

		.customer-receipt__head {
			flex-direction: column;
			align-items: flex-start;
			gap: var(--space-base);
		}

		.customer-receipt__hero {
			grid-template-columns: 1fr;
			align-items: stretch;
		}

		.customer-receipt__paid {
			text-align: left;
		}

		.customer-receipt__facts {
			grid-template-columns: 1fr;
			gap: var(--space-base);
		}
	}

	// The Save-as-PDF path: clean page, ink on white, no app chrome, whichever theme the screen was using.
	@media print {
		.customer-receipt {
			min-height: 0;
			background: #fff;
			color: #000;
		}

		.customer-receipt__notice {
			display: none;
		}

		.customer-receipt__doc {
			max-width: none;
			margin: 0;
			border: 0;
			border-radius: 0;
			box-shadow: none;
		}

		.customer-receipt__title,
		.customer-receipt__brand-name,
		.customer-receipt__recipient-name,
		.customer-receipt__fact dd {
			color: #000;
		}

		.customer-receipt__note,
		.customer-receipt__recipient-line,
		.customer-receipt__recipient-label,
		.customer-receipt__fact dt,
		.customer-receipt__details h3,
		.customer-receipt__details p {
			color: #333;
		}

		.customer-receipt__hero,
		.customer-receipt__paid {
			break-inside: avoid;
		}
	}
</style>
