<script lang="ts">
	import type { Snippet } from 'svelte';
	import type { CustomerJobReportDocument } from '$lib/jobs/report-types';

	// The customer's copy of a work report, and the only drawing of it there is. The token page hands it a
	// document resolved from a link; Preview as client hands it the same document read straight from the
	// database. Neither filters anything here -- whatever is missing from `doc` was withheld before it left
	// the database.
	//
	// It borrows nothing from the app shell on purpose. A customer sees a document, not our software. There is
	// no Jobber equivalent to copy from, so this is a fresh design built to sit beside the invoice and quote
	// documents.
	let {
		doc,
		fileHref,
		notice
	}: {
		doc: CustomerJobReportDocument;
		fileHref: (attachmentId: string) => string;
		/** A strip above the document, for anything staff need told that the customer must never see. */
		notice?: Snippet;
	} = $props();

	const longDate = new Intl.DateTimeFormat('en-US', { dateStyle: 'medium' });

	function formatDate(value: string | null) {
		return value ? longDate.format(new Date(`${value}T00:00`)) : null;
	}

	function formatMoney(minor: number) {
		return new Intl.NumberFormat('en-US', {
			style: 'currency',
			currency: doc.job.currency_code
		}).format(minor / 100);
	}

	const brandInitials = $derived.by(() => {
		const name = (doc.business.name ?? '').trim();
		if (!name) return '—';
		const words = name.split(/\s+/).filter(Boolean);
		if (words.length === 1) return words[0].slice(0, 2).toUpperCase();
		return (words[0][0] + words[words.length - 1][0]).toUpperCase();
	});

	const customerName = $derived(
		doc.client.company_name?.trim() || doc.client.display_name || 'Customer'
	);

	const propertyLines = $derived.by(() => {
		const property = doc.property;
		return [
			property.address_line1,
			property.address_line2,
			[property.city, property.state_region, property.postal_code].filter(Boolean).join(', ')
		].filter((line): line is string => Boolean(line && line.trim()));
	});

	const showMoney = $derived(doc.service_details?.totals != null);
</script>

<div class="customer-job-report">
	{#if notice}
		<div class="customer-job-report__notice">{@render notice()}</div>
	{/if}

	<article class="customer-job-report__doc">
		<div class="customer-job-report__brandbar"></div>

		<header class="customer-job-report__head">
			<div class="customer-job-report__brand">
				<div class="customer-job-report__brand-mark" aria-hidden="true">{brandInitials}</div>
				<div class="customer-job-report__brand-name">{doc.business.name ?? 'Your contractor'}</div>
			</div>
			<div class="customer-job-report__eyebrow">
				<div class="customer-job-report__kicker">Work report</div>
				<div class="customer-job-report__number">Job #{doc.job.job_number}</div>
			</div>
		</header>

		<section class="customer-job-report__hero">
			<h1 class="customer-job-report__title">{doc.job.title || 'Completed work'}</h1>
			<p class="customer-job-report__for">For {customerName}</p>
			{#if propertyLines.length}
				<p class="customer-job-report__property">{propertyLines.join(', ')}</p>
			{/if}
		</section>

		{#if doc.summary}
			<section class="customer-job-report__section">
				<h2 class="customer-job-report__section-title">Summary</h2>
				<p class="customer-job-report__summary">{doc.summary}</p>
			</section>
		{/if}

		{#if doc.photos.length > 0}
			<section class="customer-job-report__section">
				<h2 class="customer-job-report__section-title">Photos</h2>
				<div class="customer-job-report__photos">
					{#each doc.photos as photo (photo.attachment_id)}
						<img
							class="customer-job-report__photo"
							src={fileHref(photo.attachment_id)}
							alt={photo.file_name}
							loading="lazy"
						/>
					{/each}
				</div>
			</section>
		{/if}

		{#if doc.checklist.length > 0}
			<section class="customer-job-report__section">
				<h2 class="customer-job-report__section-title">Checklist</h2>
				<div class="customer-job-report__checklist">
					{#each doc.checklist as visit (visit.visit_id)}
						<div class="customer-job-report__checklist-visit">
							{#if visit.visit_date}
								<h3 class="customer-job-report__checklist-visit-date">
									{formatDate(visit.visit_date)}
								</h3>
							{/if}
							<ul class="customer-job-report__checklist-items">
								{#each visit.items as item (item.item_id)}
									<li class="customer-job-report__checklist-item">
										<span class="customer-job-report__checklist-label">{item.label}</span>
										<span class="customer-job-report__checklist-value">
											{#if typeof item.value === 'boolean'}
												{item.value ? 'Yes' : 'No'}
											{:else}
												{item.value}
											{/if}
										</span>
									</li>
								{/each}
							</ul>
						</div>
					{/each}
				</div>
			</section>
		{/if}

		{#if doc.service_details}
			<section class="customer-job-report__section">
				<h2 class="customer-job-report__section-title">Work completed</h2>
				<table class="customer-job-report__lines">
					<thead>
						<tr>
							<th scope="col">Product / service</th>
							{#if showMoney}
								<th scope="col" class="customer-job-report__num">Qty</th>
								<th scope="col" class="customer-job-report__num">Amount</th>
							{/if}
						</tr>
					</thead>
					<tbody>
						{#each doc.service_details.lines as line (line.line_id)}
							<tr>
								<td>
									<div class="customer-job-report__item-name">{line.name}</div>
									{#if line.description}
										<p class="customer-job-report__item-desc">{line.description}</p>
									{/if}
								</td>
								{#if showMoney}
									<td class="customer-job-report__num">
										{line.quantity ?? ''}
										{line.unit_label ?? ''}
									</td>
									<td class="customer-job-report__num customer-job-report__num--total">
										{line.line_total_minor !== undefined ? formatMoney(line.line_total_minor) : ''}
									</td>
								{/if}
							</tr>
						{/each}
						{#if doc.service_details.lines.length === 0}
							<tr>
								<td colspan={showMoney ? 3 : 1}>Nothing has been listed on this report.</td>
							</tr>
						{/if}
					</tbody>
				</table>

				{#if doc.service_details.totals}
					<dl class="customer-job-report__totals">
						<div class="customer-job-report__total-row">
							<dt>Subtotal</dt>
							<dd>{formatMoney(doc.service_details.totals.subtotal_minor)}</dd>
						</div>
						{#if doc.service_details.totals.discount_minor > 0}
							<div class="customer-job-report__total-row customer-job-report__total-row--credit">
								<dt>Discount</dt>
								<dd>−{formatMoney(doc.service_details.totals.discount_minor)}</dd>
							</div>
						{/if}
						{#if doc.service_details.totals.tax_minor > 0}
							<div class="customer-job-report__total-row">
								<dt>Tax</dt>
								<dd>{formatMoney(doc.service_details.totals.tax_minor)}</dd>
							</div>
						{/if}
						<div class="customer-job-report__total-row customer-job-report__total-row--total">
							<dt>Total</dt>
							<dd>{formatMoney(doc.service_details.totals.total_minor)}</dd>
						</div>
					</dl>
				{/if}
			</section>
		{/if}

		{#if doc.signature}
			<section class="customer-job-report__section">
				<h2 class="customer-job-report__section-title">Signed off</h2>
				<div class="customer-job-report__signature">
					<p class="customer-job-report__signature-statement">“{doc.signature.statement}”</p>
					<p class="customer-job-report__signature-signer">
						{doc.signature.signer_name}{doc.signature.signer_role
							? ` · ${doc.signature.signer_role}`
							: ''}
					</p>
					<p class="customer-job-report__signature-meta">
						{new Intl.DateTimeFormat('en-US', { dateStyle: 'medium', timeStyle: 'short' }).format(
							new Date(doc.signature.collected_at)
						)}
					</p>
				</div>
			</section>
		{/if}
	</article>
</div>

<style lang="scss">
	.customer-job-report {
		min-height: 100vh;
		background: var(--color-surface--background);
		color: var(--color-text);
		font-family: var(--typography--fontFamily-normal);
		padding-bottom: var(--space-largest);
	}

	.customer-job-report__notice {
		max-width: 820px;
		margin: var(--space-large) auto 0;
		padding: 0 var(--space-large);
	}

	.customer-job-report__doc {
		max-width: 820px;
		margin: var(--space-large) auto var(--space-extravagant);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		box-shadow: var(--shadow-high);
		overflow: hidden;
	}

	.customer-job-report__brandbar {
		height: 5px;
		background: linear-gradient(90deg, var(--color-job) 0%, var(--color-brand) 100%);
	}

	.customer-job-report__head {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-large);
		padding: var(--space-larger) var(--space-largest) var(--space-large);
	}

	.customer-job-report__brand {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
	}

	.customer-job-report__brand-mark {
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

	.customer-job-report__brand-name {
		font-family: var(--typography--fontFamily-display);
		font-weight: 700;
		font-size: var(--typography--fontSize-larger);
		color: var(--color-heading);
		line-height: var(--typography--lineHeight-minuscule);
	}

	.customer-job-report__eyebrow {
		text-align: right;
	}

	.customer-job-report__kicker {
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		letter-spacing: 0.14em;
		text-transform: uppercase;
		color: var(--color-text--secondary);
	}

	.customer-job-report__number {
		font-family: var(--typography--fontFamily-display);
		font-weight: 700;
		font-size: var(--typography--fontSize-largest);
		color: var(--color-heading);
		line-height: var(--typography--lineHeight-minuscule);
		font-variant-numeric: tabular-nums;
	}

	.customer-job-report__hero {
		padding: var(--space-smaller) var(--space-largest) var(--space-large);
	}

	.customer-job-report__title {
		margin: 0;
		font-family: var(--typography--fontFamily-display);
		font-weight: 600;
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-base);
		color: var(--color-heading);
	}

	.customer-job-report__for {
		margin: var(--space-small) 0 0;
		font-size: var(--typography--fontSize-base);
		color: var(--color-text--secondary);
	}

	.customer-job-report__property {
		margin: var(--space-smallest) 0 0;
		font-size: var(--typography--fontSize-base);
		color: var(--color-text--secondary);
	}

	.customer-job-report__section {
		padding: var(--space-large) var(--space-largest);
		border-top: 1px solid var(--color-border);
	}

	.customer-job-report__section-title {
		margin: 0 0 var(--space-base);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		letter-spacing: 0.1em;
		text-transform: uppercase;
		color: var(--color-text--secondary);
	}

	.customer-job-report__summary {
		margin: 0;
		color: var(--color-text);
		line-height: var(--typography--lineHeight-larger);
		white-space: pre-wrap;
	}

	.customer-job-report__photos {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
		gap: var(--space-base);
	}

	.customer-job-report__photo {
		width: 100%;
		aspect-ratio: 4 / 3;
		object-fit: cover;
		border-radius: var(--radius-base);
		border: 1px solid var(--color-border);
		background: var(--color-surface--background--subtle);
	}

	.customer-job-report__checklist {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}

	.customer-job-report__checklist-visit-date {
		margin: 0 0 var(--space-small);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		color: var(--color-heading);
	}

	.customer-job-report__checklist-items {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.customer-job-report__checklist-item {
		display: flex;
		justify-content: space-between;
		gap: var(--space-base);
		padding-bottom: var(--space-small);
		border-bottom: 1px solid var(--color-border);
		font-size: var(--typography--fontSize-base);
	}

	.customer-job-report__checklist-label {
		color: var(--color-text);
	}

	.customer-job-report__checklist-value {
		flex-shrink: 0;
		color: var(--color-heading);
		font-weight: 600;
		text-align: right;
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
		padding: 0 0 var(--space-small);
		border-bottom: 2px solid var(--color-heading);
	}

	.customer-job-report__num {
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

	.customer-job-report__item-name {
		font-weight: 600;
		color: var(--color-heading);
	}

	.customer-job-report__item-desc {
		margin: var(--space-smallest) 0 0;
		font-size: var(--typography--fontSize-base);
		color: var(--color-text--secondary);
		white-space: pre-wrap;
	}

	.customer-job-report__num--total {
		font-weight: 600;
		color: var(--color-heading);
	}

	.customer-job-report__totals {
		margin: var(--space-base) 0 0;
		margin-left: auto;
		max-width: 320px;
	}

	.customer-job-report__total-row {
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
	}

	.customer-job-report__signature {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
	}

	.customer-job-report__signature-statement {
		margin: 0;
		color: var(--color-text);
		font-style: italic;
	}

	.customer-job-report__signature-signer {
		margin: 0;
		color: var(--color-heading);
		font-weight: 600;
	}

	.customer-job-report__signature-meta {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	@media (max-width: 720px) {
		.customer-job-report__head,
		.customer-job-report__hero,
		.customer-job-report__section {
			padding-left: var(--space-large);
			padding-right: var(--space-large);
		}
	}

	// The Save-as-PDF path: clean page, ink on white, no app chrome, whichever theme the screen was using.
	@media print {
		.customer-job-report {
			min-height: 0;
			background: #fff;
			color: #000;
		}

		.customer-job-report__notice {
			display: none;
		}

		.customer-job-report__doc {
			max-width: none;
			margin: 0;
			border: 0;
			border-radius: 0;
			box-shadow: none;
		}

		.customer-job-report__title,
		.customer-job-report__number,
		.customer-job-report__brand-name,
		.customer-job-report__item-name,
		.customer-job-report__num--total,
		.customer-job-report__checklist-value,
		.customer-job-report__signature-signer {
			color: #000;
		}

		.customer-job-report__for,
		.customer-job-report__property,
		.customer-job-report__kicker,
		.customer-job-report__section-title,
		.customer-job-report__item-desc,
		thead th {
			color: #333;
		}

		.customer-job-report__section {
			break-inside: avoid;
		}
	}
</style>
