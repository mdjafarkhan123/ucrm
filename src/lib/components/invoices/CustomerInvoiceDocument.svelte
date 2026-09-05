<script lang="ts">
	import type { Snippet } from 'svelte';
	import type {
		CustomerInvoiceDocument,
		CustomerInvoiceLine
	} from '$lib/invoices/customer-document';

	// The customer's copy of a bill, and the only drawing of it there is. The token page hands it a document
	// resolved from a link; Preview as client hands it the same document read straight from the database.
	// Neither one filters anything here — whatever is missing from `doc` was withheld before it left the
	// database, so there is no hidden price sitting in the page source waiting to be read out.
	//
	// It borrows nothing from the app shell on purpose. A customer sees a document, not our software. The
	// look is a 1:1 build of Design/invoices/customer-invoice-mockup.html on real UCRM tokens.
	let {
		doc,
		notice
	}: {
		doc: CustomerInvoiceDocument;
		/** A strip above the document, for anything staff need told that the customer must never see. */
		notice?: Snippet;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat('en-US', { style: 'currency', currency: doc.invoice.currency_code })
	);
	const longDate = new Intl.DateTimeFormat('en-US', { dateStyle: 'medium' });

	function formatDate(value: string | null) {
		return value ? longDate.format(new Date(value)) : null;
	}

	function formatMoney(minor: number) {
		return money.format(minor / 100);
	}

	// The customer is told where their bill stands in their own words. Our internal names mean nothing to
	// them and are none of their business.
	type Tone = 'warning' | 'critical' | 'success' | 'inactive';
	const statusText: Record<string, string> = {
		draft: 'Draft',
		awaiting_payment: 'Awaiting payment',
		past_due: 'Past due',
		paid: 'Paid',
		voided: 'Voided',
		bad_debt: 'Written off'
	};
	const statusTone: Record<string, Tone> = {
		draft: 'inactive',
		awaiting_payment: 'warning',
		past_due: 'critical',
		paid: 'success',
		voided: 'inactive',
		bad_debt: 'inactive'
	};
	const tone = $derived(statusTone[doc.invoice.status] ?? 'inactive');
	const statusLabel = $derived(statusText[doc.invoice.status] ?? doc.invoice.status);

	// Two capital letters from the business name, for the corner mark — the same first-and-last-initial rule
	// the mockup shows.
	const brandInitials = $derived.by(() => {
		const name = (doc.business.name ?? '').trim();
		if (!name) return '—';
		const words = name.split(/\s+/).filter(Boolean);
		if (words.length === 1) return words[0].slice(0, 2).toUpperCase();
		return (words[0][0] + words[words.length - 1][0]).toUpperCase();
	});

	const customerName = $derived(
		doc.customer.company_name?.trim() || doc.customer.display_name || 'Customer'
	);

	function addressLines(a: {
		address_line1?: string | null;
		address_line2?: string | null;
		city?: string | null;
		state_region?: string | null;
		postal_code?: string | null;
	}) {
		return [
			a.address_line1,
			a.address_line2,
			[a.city, a.state_region, a.postal_code].filter(Boolean).join(', ')
		].filter((line): line is string => Boolean(line && line.trim()));
	}

	const billingLines = $derived(
		doc.billing_address.source === 'none' ? [] : addressLines(doc.billing_address)
	);
	// One bill can cover several properties; show them all, each as its own address block.
	const serviceProperties = $derived(doc.service_properties ?? []);

	const paid = $derived(doc.invoice.status === 'paid' || doc.invoice.status === 'voided');
	const balanceMinor = $derived(doc.money?.balance_due_minor ?? 0);

	// The footer is the real payment term, not an invented disclaimer. "Net 14 · Payment due Sep 18, 2026".
	const termLabel = $derived.by(() => {
		const term = doc.invoice.payment_term_snapshot;
		if (term?.name) return term.name;
		if (term?.rule === 'on_receipt') return 'Due on receipt';
		if (term?.rule === 'net' && term.net_days != null) return `Net ${term.net_days}`;
		return null;
	});
	const dueText = $derived(formatDate(doc.invoice.due_date));

	// Which numeric columns exist. Money-withheld staff preview keeps only Qty.
	const showMoney = $derived(doc.money !== null);
	const columnCount = $derived(showMoney ? 4 : 2);

	function lineNumbers(line: CustomerInvoiceLine) {
		return line.line_kind === 'priced';
	}
</script>

{#snippet lineRows(lines: CustomerInvoiceLine[])}
	{#each lines as line (line.line_id)}
		{#if line.line_kind === 'heading'}
			<tr class="customer-invoice__row--heading">
				<th colspan={columnCount} scope="colgroup">{line.name}</th>
			</tr>
		{:else}
			<tr>
				<td>
					<div class="customer-invoice__item-name">{line.name}</div>
					{#if line.description}
						<p class="customer-invoice__item-desc">{line.description}</p>
					{/if}
					{#if line.service_date}
						<span class="customer-invoice__item-date">
							Serviced {formatDate(line.service_date)}
						</span>
					{/if}
				</td>
				<td class="customer-invoice__num customer-invoice__col-qty">
					{lineNumbers(line) ? (line.quantity ?? '') : ''}
					{line.unit_label ?? ''}
				</td>
				{#if showMoney}
					<td class="customer-invoice__num customer-invoice__col-unit">
						{lineNumbers(line) && line.unit_price_minor !== undefined
							? formatMoney(line.unit_price_minor)
							: ''}
					</td>
					<td
						class="customer-invoice__num customer-invoice__col-total customer-invoice__num--total"
					>
						{lineNumbers(line) && line.line_total_minor !== undefined
							? formatMoney(line.line_total_minor)
							: ''}
					</td>
				{/if}
			</tr>
		{/if}
	{/each}
{/snippet}

<div class="customer-invoice">
	{#if notice}
		<div class="customer-invoice__notice">{@render notice()}</div>
	{/if}

	<article class="customer-invoice__doc">
		<div class="customer-invoice__brandbar"></div>

		<header class="customer-invoice__head">
			<div class="customer-invoice__brand">
				<div class="customer-invoice__brand-mark" aria-hidden="true">{brandInitials}</div>
				<div>
					<div class="customer-invoice__brand-name">
						{doc.business.name ?? 'Your contractor'}
					</div>
				</div>
			</div>
			<div class="customer-invoice__eyebrow">
				<div class="customer-invoice__kicker">Invoice</div>
				<div class="customer-invoice__number">#{doc.invoice.invoice_number}</div>
				<span class="customer-invoice__status customer-invoice__status--{tone}">
					<span class="customer-invoice__status-dot"></span>
					{statusLabel}
				</span>
			</div>
		</header>

		<section class="customer-invoice__hero">
			<div>
				<h1 class="customer-invoice__title">{doc.invoice.subject ?? 'Invoice'}</h1>
				<p class="customer-invoice__for">
					Billed to {customerName}{#if billingLines.length}
						· {billingLines.join(', ')}{/if}
				</p>
			</div>
			{#if showMoney}
				<div class="customer-invoice__balance">
					<div class="customer-invoice__balance-label">Balance due</div>
					<div class="customer-invoice__balance-amount">{formatMoney(balanceMinor)}</div>
					{#if paid || balanceMinor <= 0}
						<div class="customer-invoice__balance-due">Paid in full</div>
					{:else if dueText}
						<div class="customer-invoice__balance-due">Due <b>{dueText}</b></div>
					{/if}
				</div>
			{/if}
		</section>

		<section class="customer-invoice__meta">
			<div class="customer-invoice__meta-block">
				<h3>Billed to</h3>
				<p class="customer-invoice__meta-strong">{customerName}</p>
				{#each billingLines as line (line)}
					<p>{line}</p>
				{/each}
			</div>
			{#if serviceProperties.length}
				<div class="customer-invoice__meta-block">
					<h3>{serviceProperties.length > 1 ? 'Service addresses' : 'Service address'}</h3>
					{#each serviceProperties as property (property.property_id)}
						{@const lines = addressLines(property)}
						{#if property.label}<p class="customer-invoice__meta-strong">{property.label}</p>{/if}
						{#each lines as line (line)}
							<p>{line}</p>
						{/each}
					{/each}
				</div>
			{/if}
			<div class="customer-invoice__meta-block">
				<h3>Details</h3>
				<dl class="customer-invoice__dates">
					<div class="customer-invoice__date">
						<dt>Issued</dt>
						<dd>{formatDate(doc.invoice.issue_date)}</dd>
					</div>
					{#if termLabel}
						<div class="customer-invoice__date">
							<dt>Terms</dt>
							<dd>{termLabel}</dd>
						</div>
					{/if}
					<div class="customer-invoice__date">
						<dt>Due date</dt>
						<dd>{dueText}</dd>
					</div>
				</dl>
			</div>
		</section>

		<section class="customer-invoice__lines">
			<table>
				<thead>
					<tr>
						<th scope="col">Product / service</th>
						<th scope="col" class="customer-invoice__num customer-invoice__col-qty">Qty</th>
						{#if showMoney}
							<th scope="col" class="customer-invoice__num customer-invoice__col-unit"
								>Unit price</th
							>
							<th scope="col" class="customer-invoice__num customer-invoice__col-total">Total</th>
						{/if}
					</tr>
				</thead>
				<tbody>
					{@render lineRows(doc.lines)}
					{#if doc.lines.length === 0}
						<tr>
							<td colspan={columnCount}>Nothing has been added to this invoice.</td>
						</tr>
					{/if}
				</tbody>
			</table>
		</section>

		{#if showMoney && doc.money}
			<section class="customer-invoice__foot">
				<div></div>
				<dl class="customer-invoice__totals">
					<div class="customer-invoice__total-row">
						<dt>Subtotal</dt>
						<dd>{formatMoney(doc.money.subtotal_minor)}</dd>
					</div>
					{#if doc.money.discount}
						<div class="customer-invoice__total-row customer-invoice__total-row--credit">
							<dt>
								{doc.money.discount.name || 'Discount'}
								{#if doc.money.discount.type === 'percentage'}
									({(doc.money.discount.value / 100).toFixed(
										doc.money.discount.value % 100 === 0 ? 0 : 2
									)}%)
								{/if}
							</dt>
							<dd>−{formatMoney(doc.money.discount.amount_minor)}</dd>
						</div>
					{/if}
					{#if doc.money.tax}
						<div class="customer-invoice__total-row">
							<dt>
								{doc.money.tax.name || 'Tax'}
								{#if doc.money.tax.rate_basis_points}
									({(doc.money.tax.rate_basis_points / 100).toFixed(
										doc.money.tax.rate_basis_points % 100 === 0 ? 0 : 2
									)}%)
								{/if}
							</dt>
							<dd>{formatMoney(doc.money.tax.amount_minor)}</dd>
						</div>
					{/if}
					<div class="customer-invoice__total-row customer-invoice__total-row--total">
						<dt>Total</dt>
						<dd>{formatMoney(doc.money.total_minor)}</dd>
					</div>

					{#if doc.money.deposit_applied_minor > 0 || doc.money.payment_received_minor > 0}
						<div class="customer-invoice__rule"></div>
						{#if doc.money.deposit_applied_minor > 0}
							<div class="customer-invoice__total-row customer-invoice__total-row--credit">
								<dt>Deposit applied</dt>
								<dd>−{formatMoney(doc.money.deposit_applied_minor)}</dd>
							</div>
						{/if}
						{#if doc.money.payment_received_minor > 0}
							<div class="customer-invoice__total-row customer-invoice__total-row--credit">
								<dt>Payment received</dt>
								<dd>−{formatMoney(doc.money.payment_received_minor)}</dd>
							</div>
						{/if}
						<div class="customer-invoice__total-row customer-invoice__total-row--balance">
							<dt>Balance due</dt>
							<dd>{formatMoney(doc.money.balance_due_minor)}</dd>
						</div>
					{/if}
				</dl>
			</section>
		{/if}

		{#if termLabel || dueText}
			<footer class="customer-invoice__terms">
				<div class="customer-invoice__terms-text">
					{#if termLabel}{termLabel}{/if}{#if termLabel && dueText}
						·
					{/if}{#if dueText}Payment due
						{dueText}{/if}
				</div>
			</footer>
		{/if}

		{#if doc.invoice.contract_disclaimer}
			<footer class="customer-invoice__disclaimer">
				<p>{doc.invoice.contract_disclaimer}</p>
			</footer>
		{/if}
	</article>
</div>

<style lang="scss">
	.customer-invoice {
		min-height: 100vh;
		background: var(--color-surface--background);
		color: var(--color-text);
		font-family: var(--typography--fontFamily-normal);
		padding-bottom: var(--space-largest);
	}

	.customer-invoice__notice {
		max-width: 820px;
		margin: var(--space-large) auto 0;
		padding: 0 var(--space-large);
	}

	.customer-invoice__doc {
		max-width: 820px;
		margin: var(--space-large) auto var(--space-extravagant);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		box-shadow: var(--shadow-high);
		overflow: hidden;
	}

	// A branded band along the very top: the invoice accent bleeding into the brand lime.
	.customer-invoice__brandbar {
		height: 5px;
		background: linear-gradient(
			90deg,
			var(--color-invoice) 0%,
			var(--color-informative) 55%,
			var(--color-brand) 100%
		);
	}

	.customer-invoice__head {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-large);
		padding: var(--space-larger) var(--space-largest) var(--space-large);
	}

	.customer-invoice__brand {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
	}

	.customer-invoice__brand-mark {
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

	.customer-invoice__brand-name {
		font-family: var(--typography--fontFamily-display);
		font-weight: 700;
		font-size: var(--typography--fontSize-larger);
		color: var(--color-heading);
		line-height: var(--typography--lineHeight-minuscule);
	}

	.customer-invoice__eyebrow {
		text-align: right;
	}

	.customer-invoice__kicker {
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		letter-spacing: 0.14em;
		text-transform: uppercase;
		color: var(--color-text--secondary);
	}

	.customer-invoice__number {
		font-family: var(--typography--fontFamily-display);
		font-weight: 700;
		font-size: var(--typography--fontSize-largest);
		color: var(--color-heading);
		line-height: var(--typography--lineHeight-minuscule);
		font-variant-numeric: tabular-nums;
	}

	.customer-invoice__status {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		margin-top: var(--space-small);
		padding: var(--space-smaller) var(--space-slim) var(--space-smaller) var(--space-small);
		border-radius: 999px;
		font-size: var(--typography--fontSize-small);
		font-weight: 600;

		&--warning {
			background: var(--color-warning--surface);
			color: var(--color-warning--onSurface);
		}
		&--critical {
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
		}
		&--success {
			background: var(--color-success--surface);
			color: var(--color-success--onSurface);
		}
		&--inactive {
			background: var(--color-inactive--surface);
			color: var(--color-inactive--onSurface);
		}
	}

	.customer-invoice__status-dot {
		width: 7px;
		height: 7px;
		border-radius: 50%;
		background: currentcolor;
		opacity: 0.7;
	}

	.customer-invoice__hero {
		display: grid;
		grid-template-columns: 1fr auto;
		gap: var(--space-larger);
		align-items: end;
		padding: var(--space-smaller) var(--space-largest) var(--space-large);
	}

	.customer-invoice__title {
		margin: 0;
		font-family: var(--typography--fontFamily-display);
		font-weight: 600;
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-base);
		color: var(--color-heading);
		text-wrap: balance;
		max-width: 26ch;
	}

	.customer-invoice__for {
		margin: var(--space-small) 0 0;
		font-size: var(--typography--fontSize-base);
		color: var(--color-text--secondary);
	}

	.customer-invoice__balance {
		text-align: right;
		padding: var(--space-base) var(--space-large);
		border-radius: var(--radius-large);
		background: var(--color-invoice--surface);
		border: 1px solid var(--color-invoice--surface);
		min-width: 210px;
	}

	.customer-invoice__balance-label {
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		letter-spacing: 0.12em;
		text-transform: uppercase;
		color: var(--color-invoice--onSurface);
	}

	.customer-invoice__balance-amount {
		font-family: var(--typography--fontFamily-display);
		font-weight: 800;
		font-size: var(--typography--fontSize-jumbo);
		line-height: var(--typography--lineHeight-minuscule);
		color: var(--color-heading);
		font-variant-numeric: tabular-nums;
		margin-top: var(--space-smaller);
	}

	.customer-invoice__balance-due {
		font-size: var(--typography--fontSize-small);
		color: var(--color-invoice--onSurface);
		margin-top: var(--space-smaller);

		b {
			font-weight: 600;
		}
	}

	.customer-invoice__meta {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: var(--space-large);
		margin: 0 var(--space-largest);
		padding: var(--space-base) 0;
		border-top: 1px solid var(--color-border);
		border-bottom: 1px solid var(--color-border);
	}

	.customer-invoice__meta-block {
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
		}
	}

	.customer-invoice__meta-strong {
		font-weight: 600;
		color: var(--color-heading) !important;
	}

	.customer-invoice__dates {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
	}

	.customer-invoice__date {
		display: flex;
		justify-content: space-between;
		gap: var(--space-slim);
		font-size: var(--typography--fontSize-base);

		dt {
			color: var(--color-text--secondary);
		}

		dd {
			margin: 0;
			font-weight: 600;
			color: var(--color-heading);
			font-variant-numeric: tabular-nums;
		}
	}

	.customer-invoice__lines {
		padding: var(--space-small) var(--space-largest) 0;
		overflow-x: auto;
	}

	table {
		width: 100%;
		border-collapse: collapse;
	}

	thead th {
		text-align: left;
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--color-text--secondary);
		padding: var(--space-base) 0 var(--space-small);
		border-bottom: 2px solid var(--color-heading);
	}

	.customer-invoice__num {
		text-align: right;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}

	tbody td {
		padding: var(--space-base) 0;
		border-bottom: 1px solid var(--color-border);
		vertical-align: top;
		font-size: var(--typography--fontSize-base);
	}

	.customer-invoice__item-name {
		font-weight: 600;
		color: var(--color-heading);
	}

	.customer-invoice__item-desc {
		margin: var(--space-smallest) 0 0;
		font-size: var(--typography--fontSize-base);
		color: var(--color-text--secondary);
		max-width: 52ch;
		white-space: pre-wrap;
	}

	.customer-invoice__item-date {
		display: inline-block;
		margin-top: var(--space-smaller);
		font-size: var(--typography--fontSize-small);
		color: var(--color-invoice--onSurface);
		background: var(--color-invoice--surface);
		padding: var(--space-smallest) var(--space-small);
		border-radius: var(--radius-small);
	}

	.customer-invoice__num--total {
		font-weight: 600;
		color: var(--color-heading);
	}

	.customer-invoice__row--heading th {
		text-align: left;
		padding: var(--space-large) 0 var(--space-small);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 700;
		border-bottom: 1px solid var(--color-border);
	}

	.customer-invoice__col-qty {
		width: 66px;
	}
	.customer-invoice__col-unit {
		width: 120px;
	}
	.customer-invoice__col-total {
		width: 120px;
	}

	.customer-invoice__foot {
		display: grid;
		grid-template-columns: 1fr minmax(300px, 340px);
		gap: var(--space-larger);
		padding: var(--space-large) var(--space-largest) var(--space-small);
	}

	.customer-invoice__totals {
		margin: 0;
	}

	.customer-invoice__total-row {
		display: flex;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-smaller) 0;
		font-size: var(--typography--fontSize-base);

		dt {
			color: var(--color-text--secondary);
		}

		dd {
			margin: 0;
			font-variant-numeric: tabular-nums;
			font-weight: 600;
			color: var(--color-text);
		}

		&--credit dd {
			color: var(--color-success);
		}

		&--total {
			padding-top: var(--space-small);
			border-top: 2px solid var(--color-heading);

			dt {
				color: var(--color-heading);
				font-weight: 600;
			}
			dd {
				color: var(--color-heading);
				font-weight: 700;
			}
		}

		&--balance {
			margin-top: var(--space-small);
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-slim, 12px);
			background: var(--color-surface--reverse);
			align-items: center;

			dt {
				color: var(--color-text--reverse);
				font-weight: 600;
			}
			dd {
				color: var(--color-text--reverse);
				font-family: var(--typography--fontFamily-display);
				font-weight: 800;
				font-size: var(--typography--fontSize-larger);
			}
		}
	}

	.customer-invoice__rule {
		height: 1px;
		background: var(--color-border);
		margin: var(--space-smaller) 0;
	}

	.customer-invoice__terms {
		margin: var(--space-small) var(--space-largest) 0;
		padding: var(--space-base) 0 var(--space-larger);
		border-top: 1px solid var(--color-border);
	}

	.customer-invoice__terms-text {
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
		max-width: 62ch;
		line-height: var(--typography--lineHeight-larger);
	}

	// A distinct block from the payment-terms footer above: what the customer owes is not the same thing as
	// what they are agreeing to, and each gets its own border rather than sharing one.
	.customer-invoice__disclaimer {
		margin: 0 var(--space-largest) var(--space-largest);
		padding-top: var(--space-base);
		border-top: 1px solid var(--color-border);
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
		white-space: pre-wrap;

		p {
			margin: 0;
		}
	}

	@media (max-width: 720px) {
		.customer-invoice__head,
		.customer-invoice__hero,
		.customer-invoice__lines,
		.customer-invoice__foot {
			padding-left: var(--space-large);
			padding-right: var(--space-large);
		}

		.customer-invoice__meta {
			margin: 0 var(--space-large);
			grid-template-columns: 1fr;
			gap: var(--space-base);
		}

		.customer-invoice__hero {
			grid-template-columns: 1fr;
			align-items: stretch;
		}

		.customer-invoice__balance {
			text-align: left;
		}

		.customer-invoice__foot {
			grid-template-columns: 1fr;
		}

		.customer-invoice__col-unit {
			display: none;
		}
	}

	// The Save-as-PDF path: clean page, ink on white, no app chrome, whichever theme the screen was using.
	@media print {
		.customer-invoice {
			min-height: 0;
			background: #fff;
			color: #000;
		}

		.customer-invoice__notice {
			display: none;
		}

		.customer-invoice__doc {
			max-width: none;
			margin: 0;
			border: 0;
			border-radius: 0;
			box-shadow: none;
		}

		.customer-invoice__item-date {
			background: none;
			padding: 0;
			color: #333;
		}

		.customer-invoice__title,
		.customer-invoice__number,
		.customer-invoice__brand-name,
		.customer-invoice__balance-amount,
		.customer-invoice__item-name,
		.customer-invoice__num--total,
		.customer-invoice__date dd {
			color: #000;
		}

		.customer-invoice__for,
		.customer-invoice__meta-block p,
		.customer-invoice__kicker,
		.customer-invoice__total-row dt,
		.customer-invoice__terms-text,
		.customer-invoice__disclaimer,
		thead th {
			color: #333;
		}

		tbody tr,
		.customer-invoice__total-row--balance {
			break-inside: avoid;
		}
	}
</style>
