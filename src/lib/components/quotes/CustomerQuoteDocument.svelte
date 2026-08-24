<script lang="ts">
	import Badge from '$lib/components/ui/Badge.svelte';
	import SignaturePad from '$lib/components/quotes/SignaturePad.svelte';
	import { emptySignature, signatureIsGiven, type SignatureValue } from '$lib/quotes/signature';
	import type { CustomerQuoteDocument, CustomerQuoteLine } from '$lib/quotes/customer-document';
	import type { Snippet } from 'svelte';
	import buildingIcon from '@tabler/icons/outline/building-store.svg?raw';
	import fileIcon from '@tabler/icons/outline/file-text.svg?raw';
	import downloadIcon from '@tabler/icons/outline/download.svg?raw';

	// The customer's copy of a quote, and the only drawing of it there is. The token page hands it a
	// document resolved from a link; Preview as client hands it the same document read straight from the
	// database. Neither one filters anything here — whatever is missing from `doc` was withheld before it
	// left the database, so there is no hidden price sitting in the page source waiting to be read out.
	//
	// It borrows nothing from the app shell on purpose. A customer sees a document, not our software.
	let {
		doc,
		decisions = 'hidden',
		onDecide,
		fileHref,
		notice
	}: {
		doc: CustomerQuoteDocument;
		/**
		 * `hidden` draws no approve/decline controls at all, for a document nobody can answer.
		 * `inert` draws them disabled for staff preview, so the person sending the quote can see what
		 * their client will be asked. `live` is the customer's own copy, where the buttons work.
		 */
		decisions?: 'hidden' | 'inert' | 'live';
		/**
		 * Sends the customer's answer. It throws with a sentence to show them when the answer could not
		 * be recorded — usually because the quote moved on while the page was open.
		 */
		onDecide?: (
			outcome: 'approved' | 'changes_requested',
			note: string,
			signature: SignatureValue | null
		) => Promise<void>;
		/** Where a file on this document is served from, which differs for a customer and for staff. */
		fileHref: (attachmentId: string, size?: 'thumb') => string;
		/** A line above the document, for anything staff need told that the customer must never see. */
		notice?: Snippet;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat('en-US', { style: 'currency', currency: doc.document.currency_code })
	);
	const longDate = new Intl.DateTimeFormat('en-US', { dateStyle: 'medium' });

	function formatDate(value: string | null) {
		return value ? longDate.format(new Date(value)) : null;
	}

	// The customer is told where their quote stands in their own words. Our internal names for the same
	// states — draft, archived, converted — mean nothing to them and are none of their business.
	const statusText: Record<string, string> = {
		draft: 'Draft',
		awaiting_response: 'Awaiting your response',
		changes_requested: 'Changes requested',
		approved: 'Approved',
		declined: 'Declined',
		archived: 'No longer current',
		converted: 'Approved'
	};
	const statusTone: Record<
		string,
		'success' | 'warning' | 'critical' | 'inactive' | 'informative'
	> = {
		draft: 'inactive',
		awaiting_response: 'informative',
		changes_requested: 'warning',
		approved: 'success',
		declined: 'critical',
		archived: 'inactive',
		converted: 'success'
	};

	const propertyLines = $derived(
		[
			doc.document.service_address_line1,
			doc.document.service_address_line2,
			[
				doc.document.service_city,
				doc.document.service_state_region,
				doc.document.service_postal_code
			]
				.filter(Boolean)
				.join(', '),
			doc.document.service_country
		].filter((line): line is string => Boolean(line && line.trim()))
	);

	// Dates only. The quote number is the heading right beside this, and Jobber's client view does not
	// repeat it either.
	const facts = $derived(
		[
			{ label: 'Sent on', value: formatDate(doc.quote.sent_at) },
			{
				label: doc.quote.decision === 'declined' ? 'Declined on' : 'Approved on',
				value: doc.quote.decision ? formatDate(doc.quote.decided_at) : null
			}
		].filter((fact) => fact.value)
	);

	// Everything the quote asks for outright, then the optional extras. Position order inside each group
	// is the order staff put them in.
	const requiredLines = $derived(doc.lines.filter((line) => line.selection_kind !== 'optional'));
	const optionalLines = $derived(doc.lines.filter((line) => line.selection_kind === 'optional'));

	const showQuantity = $derived(doc.document.show_quantities);
	const showUnitPrice = $derived(doc.document.show_unit_prices);
	const showLineTotal = $derived(doc.document.show_line_totals);
	const columnCount = $derived(
		1 + [showQuantity, showUnitPrice, showLineTotal].filter(Boolean).length
	);

	// Answering is two presses, not one. Approving a quote is agreeing to spend money, and asking for
	// changes without saying what to change tells the office nothing — so both open a short step where
	// the customer can see what they are about to do and back out of it.
	type DecisionStep = 'idle' | 'approved' | 'changes_requested' | 'sent';
	let step = $state<DecisionStep>('idle');
	let message = $state('');
	let sending = $state(false);
	let problem = $state('');
	// Signing is part of approving, so the pad lives in the approve step and empties with it.
	let signature = $state(emptySignature());
	// Kept only so the page can say the name back to the person who just typed it. Nothing is read back
	// from the server for this: the customer's copy is not a place to look signatures up.
	let signedName = $state('');

	// The quote is only open to an answer while it is waiting for one. Once it has been answered, or
	// handed back to the office, the buttons go and the chip at the top says where it stands.
	//
	// Preview follows the same rule rather than always drawing them, because a preview that shows two
	// buttons on an answered quote is telling staff something about their client's screen that is not
	// true. A draft is the one addition: nobody can answer it yet, but checking what will be asked is
	// exactly why somebody previews a quote before sending it.
	const answerable = $derived(doc.quote.status === 'awaiting_response');
	const showDecisions = $derived(
		decisions === 'inert'
			? answerable || doc.quote.status === 'draft'
			: decisions === 'live' && (answerable || step === 'sent')
	);

	function openStep(next: 'approved' | 'changes_requested') {
		step = next;
		problem = '';
	}

	function cancelStep() {
		step = 'idle';
		message = '';
		problem = '';
		signature = emptySignature();
	}

	async function confirmStep() {
		if (sending || step === 'idle' || step === 'sent' || !onDecide) return;
		const outcome = step;
		if (outcome === 'changes_requested' && message.trim().length < 3) {
			problem = 'Tell them what you would like changed.';
			return;
		}

		// Signing is offered, not demanded, so an empty pad is a perfectly good answer. Half a signature
		// is not: a drawing nobody put their name to, or a name that promised a drawing and has none.
		const signed = outcome === 'approved' && signatureIsGiven(signature);
		if (outcome === 'approved') {
			if (signature.method === 'drawn' && signature.image && !signatureIsGiven(signature)) {
				problem = 'Type your name beside your signature.';
				return;
			}
			if (signed && signature.method === 'drawn' && !signature.image) {
				problem = 'Draw your signature, or switch to typing it.';
				return;
			}
		}

		sending = true;
		problem = '';
		try {
			await onDecide(outcome, message.trim(), signed ? signature : null);
			signedName = signed ? signature.name.trim() : '';
			step = 'sent';
			message = '';
			signature = emptySignature();
		} catch (error) {
			problem =
				error instanceof Error ? error.message : 'That could not be sent. Please try again.';
		} finally {
			sending = false;
		}
	}

	function isImage(mimeType: string) {
		return mimeType.startsWith('image/');
	}

	function fileSize(bytes: number) {
		if (bytes < 1024) return `${bytes} B`;
		if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
		return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
	}
</script>

{#snippet lineRows(lines: CustomerQuoteLine[])}
	{#each lines as line (line.id)}
		{#if line.line_kind === 'heading'}
			<tr class="customer-quote__row customer-quote__row--heading">
				<th colspan={columnCount} scope="colgroup">{line.name}</th>
			</tr>
		{:else}
			<tr class="customer-quote__row">
				<td class="customer-quote__cell customer-quote__cell--name">
					<div class="customer-quote__item">
						{#if line.image_attachment_id}
							<img
								class="customer-quote__thumb"
								src={fileHref(line.image_attachment_id, 'thumb')}
								alt=""
								loading="lazy"
							/>
						{/if}
						<div>
							<p class="customer-quote__item-name">{line.name}</p>
							{#if line.description}
								<p class="customer-quote__item-description">{line.description}</p>
							{/if}
							{#if line.selection_kind === 'optional'}
								<p class="customer-quote__item-tag">Optional</p>
							{/if}
						</div>
					</div>
				</td>
				{#if showQuantity}
					<td class="customer-quote__cell customer-quote__cell--number">
						{line.line_kind === 'priced' ? `${line.quantity ?? ''}` : ''}
						{line.unit_label ?? ''}
					</td>
				{/if}
				{#if showUnitPrice}
					<td class="customer-quote__cell customer-quote__cell--number">
						{line.line_kind === 'priced' && line.unit_price_minor !== undefined
							? money.format(line.unit_price_minor / 100)
							: ''}
					</td>
				{/if}
				{#if showLineTotal}
					<td class="customer-quote__cell customer-quote__cell--number">
						{line.line_kind === 'priced' && line.line_total_minor !== undefined
							? money.format(line.line_total_minor / 100)
							: ''}
					</td>
				{/if}
			</tr>
		{/if}
	{/each}
{/snippet}

<div class="customer-quote">
	<header class="customer-quote__brand">
		<span class="customer-quote__brand-mark" aria-hidden="true">{@html buildingIcon}</span>
		<span class="customer-quote__brand-name">{doc.business.name ?? 'Your contractor'}</span>
	</header>

	{#if notice}
		<div class="customer-quote__notice">{@render notice()}</div>
	{/if}

	<div class="customer-quote__grid">
		<article class="customer-quote__paper">
			<div class="customer-quote__head">
				<div>
					<h1 class="customer-quote__title">Quote #{doc.quote.quote_number}</h1>
					<Badge status={statusTone[doc.quote.status] ?? 'inactive'} size="large">
						{statusText[doc.quote.status] ?? doc.quote.status}
					</Badge>
				</div>
				<dl class="customer-quote__facts">
					{#each facts as fact (fact.label)}
						<div class="customer-quote__fact">
							<dt>{fact.label}</dt>
							<dd>{fact.value}</dd>
						</div>
					{/each}
				</dl>
			</div>

			<div class="customer-quote__parties">
				<section class="customer-quote__party">
					<h2 class="customer-quote__party-title">For</h2>
					<p class="customer-quote__party-name">
						{doc.document.client_display_name ?? doc.recipient.name}
					</p>
					{#if doc.recipient.email}
						<p class="customer-quote__party-line">{doc.recipient.email}</p>
					{/if}
				</section>
				{#if propertyLines.length > 0}
					<section class="customer-quote__party">
						<h2 class="customer-quote__party-title">Work address</h2>
						{#each propertyLines as line (line)}
							<p class="customer-quote__party-line">{line}</p>
						{/each}
					</section>
				{/if}
			</div>

			{#if doc.document.introduction}
				<p class="customer-quote__intro">{doc.document.introduction}</p>
			{/if}

			<!-- On a narrow phone the price columns cannot shrink any further, so the table scrolls inside
			     its own box rather than pushing the whole document sideways. -->
			<div class="customer-quote__table-wrap">
				<table class="customer-quote__table">
					<caption class="customer-quote__table-caption">What this quote covers</caption>
					<thead>
						<tr>
							<th scope="col">Product or service</th>
							{#if showQuantity}<th scope="col" class="customer-quote__cell--number">Qty</th>{/if}
							{#if showUnitPrice}<th scope="col" class="customer-quote__cell--number">Unit</th>{/if}
							{#if showLineTotal}<th scope="col" class="customer-quote__cell--number">Total</th
								>{/if}
						</tr>
					</thead>
					<tbody>
						{@render lineRows(requiredLines)}

						{#if optionalLines.length > 0}
							<tr class="customer-quote__row customer-quote__row--group">
								<th colspan={columnCount} scope="colgroup">
									<span class="customer-quote__group-name">Optional extras</span>
									<span class="customer-quote__group-description">
										Add any of these if you would like them included.
									</span>
								</th>
							</tr>
							{@render lineRows(optionalLines)}
						{/if}

						{#if doc.lines.length === 0}
							<tr class="customer-quote__row">
								<td class="customer-quote__cell" colspan={columnCount}>
									Nothing has been added to this quote yet.
								</td>
							</tr>
						{/if}
					</tbody>
				</table>
			</div>

			{#if doc.totals}
				<dl class="customer-quote__totals">
					<div class="customer-quote__total-row">
						<dt>Subtotal</dt>
						<dd>{money.format(doc.totals.subtotal_minor / 100)}</dd>
					</div>
					{#if doc.totals.discount_minor > 0}
						<div class="customer-quote__total-row">
							<dt>{doc.totals.discount_name || 'Discount'}</dt>
							<dd>−{money.format(doc.totals.discount_minor / 100)}</dd>
						</div>
					{/if}
					{#if doc.totals.tax_minor > 0}
						<div class="customer-quote__total-row">
							<dt>
								{doc.totals.tax_name || 'Tax'}
								{#if doc.totals.tax_rate_basis_points}
									<span class="customer-quote__total-rate">
										({(doc.totals.tax_rate_basis_points / 100).toFixed(2)}%)
									</span>
								{/if}
							</dt>
							<dd>{money.format(doc.totals.tax_minor / 100)}</dd>
						</div>
					{/if}
					<div class="customer-quote__total-row customer-quote__total-row--grand">
						<dt>Total</dt>
						<dd>{money.format(doc.totals.total_minor / 100)}</dd>
					</div>
				</dl>
			{/if}

			{#if doc.document.client_message}
				<section class="customer-quote__block">
					<h2 class="customer-quote__block-title">A note from us</h2>
					<p class="customer-quote__copy">{doc.document.client_message}</p>
				</section>
			{/if}

			{#if doc.attachments.length > 0}
				<section class="customer-quote__block">
					<h2 class="customer-quote__block-title">Attachments</h2>
					<ul class="customer-quote__files">
						{#each doc.attachments as attachment (attachment.id)}
							<li>
								<a class="customer-quote__file" href={fileHref(attachment.id)}>
									{#if isImage(attachment.mime_type)}
										<img
											class="customer-quote__file-thumb"
											src={fileHref(attachment.id, 'thumb')}
											alt={attachment.name}
											loading="lazy"
										/>
									{:else}
										<span class="customer-quote__file-icon" aria-hidden="true"
											>{@html fileIcon}</span
										>
									{/if}
									<span class="customer-quote__file-text">
										<span class="customer-quote__file-name">{attachment.name}</span>
										<span class="customer-quote__file-size">{fileSize(attachment.size_bytes)}</span>
									</span>
									<span class="customer-quote__file-download" aria-hidden="true"
										>{@html downloadIcon}</span
									>
								</a>
							</li>
						{/each}
					</ul>
				</section>
			{/if}

			{#if doc.document.contract_disclaimer}
				<footer class="customer-quote__disclaimer">
					<p>{doc.document.contract_disclaimer}</p>
				</footer>
			{/if}
		</article>

		{#if doc.totals || doc.deposit || showDecisions}
			<aside class="customer-quote__rail">
				<div class="customer-quote__rail-card">
					{#if doc.totals}
						<p class="customer-quote__rail-label">Quote total</p>
						<p class="customer-quote__rail-total">
							{money.format(doc.totals.total_minor / 100)}
						</p>
					{/if}

					{#if doc.deposit}
						<div class="customer-quote__deposit">
							<p class="customer-quote__rail-label">Deposit required</p>
							<p class="customer-quote__deposit-amount">
								{money.format(doc.deposit.required_minor / 100)}
							</p>
							{#if doc.deposit.satisfied}
								<Badge status="success" size="small">Received</Badge>
							{:else}
								<p class="customer-quote__deposit-note">
									Arrange this deposit directly with {doc.business.name ?? 'your contractor'} — this page
									does not take payment.
								</p>
							{/if}
						</div>
					{/if}

					{#if showDecisions}
						<div class="customer-quote__decisions">
							{#if step === 'sent'}
								<p class="customer-quote__decision-done">
									Thanks — {doc.business.name ?? 'the company'} has your answer.
								</p>
								{#if signedName}
									<p class="customer-quote__decision-note">Signed by {signedName}.</p>
								{/if}
							{:else if step === 'idle'}
								<button
									class="customer-quote__decision"
									type="button"
									disabled={decisions === 'inert'}
									onclick={() => openStep('approved')}>Approve</button
								>
								<button
									class="customer-quote__decision customer-quote__decision--secondary"
									type="button"
									disabled={decisions === 'inert'}
									onclick={() => openStep('changes_requested')}>Request changes</button
								>
								{#if decisions === 'inert'}
									<p class="customer-quote__decision-note">
										Only your client can use these buttons.
									</p>
								{/if}
							{:else}
								<p class="customer-quote__decision-question">
									{step === 'approved'
										? 'Happy to go ahead with this quote?'
										: 'What would you like changed?'}
								</p>
								{#if step === 'approved'}
									<div class="customer-quote__decision-signature">
										<SignaturePad
											bind:value={signature}
											idPrefix="customer-quote"
											disabled={sending || decisions === 'inert'}
										/>
									</div>
								{/if}
								<label class="customer-quote__decision-field">
									<span>{step === 'approved' ? 'Add a message (optional)' : 'Your message'}</span>
									<textarea
										bind:value={message}
										rows="3"
										maxlength="1000"
										disabled={sending}
										placeholder={step === 'approved'
											? 'Anything you want them to know'
											: 'For example: can you split this into two visits?'}></textarea>
								</label>
								{#if problem}
									<p class="customer-quote__decision-problem" role="alert">{problem}</p>
								{/if}
								<button
									class="customer-quote__decision"
									type="button"
									disabled={sending}
									onclick={() => void confirmStep()}
									>{sending
										? 'Sending…'
										: step === 'approved'
											? 'Yes, approve it'
											: 'Send this to them'}</button
								>
								<button
									class="customer-quote__decision customer-quote__decision--secondary"
									type="button"
									disabled={sending}
									onclick={cancelStep}>Cancel</button
								>
							{/if}
						</div>
					{/if}
				</div>
			</aside>
		{/if}
	</div>
</div>

<style lang="scss">
	.customer-quote {
		min-height: 100vh;
		background: var(--color-surface--background);
		color: var(--color-text);
		padding-bottom: var(--space-largest);
	}

	.customer-quote__brand {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-base) var(--space-large);
		background: var(--color-surface);
		border-bottom: 1px solid var(--color-border);
	}

	.customer-quote__brand-mark :global(svg) {
		width: 22px;
		height: 22px;
		color: var(--color-brand);
	}

	.customer-quote__brand-name {
		font-size: var(--typography--fontSize-large);
		font-weight: 700;
		color: var(--color-heading);
	}

	.customer-quote__notice {
		max-width: 1160px;
		margin: var(--space-base) auto 0;
		padding: 0 var(--space-large);
	}

	.customer-quote__grid {
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		gap: var(--space-large);
		max-width: 1160px;
		margin: 0 auto;
		padding: var(--space-large);
	}

	@media (min-width: 1024px) {
		.customer-quote__grid {
			grid-template-columns: minmax(0, 1fr) 300px;
			align-items: start;
		}
	}

	.customer-quote__paper {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		padding: var(--space-largest);
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}

	.customer-quote__head {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		gap: var(--space-large);
	}

	.customer-quote__title {
		margin: 0 0 var(--space-small);
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
		font-weight: 700;
		color: var(--color-heading);
	}

	.customer-quote__facts {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-large);
		margin: 0;
	}

	.customer-quote__fact dt {
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.customer-quote__fact dd {
		margin: 0;
		font-weight: 600;
		color: var(--color-heading);
	}

	.customer-quote__parties {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
		gap: var(--space-large);
		padding: var(--space-base) 0;
		border-top: 1px solid var(--color-border);
		border-bottom: 1px solid var(--color-border);
	}

	.customer-quote__party-title {
		margin: 0 0 var(--space-smaller);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: var(--typography--letterSpacing-loose);
		color: var(--color-text--secondary);
	}

	.customer-quote__party-name {
		margin: 0;
		font-weight: 600;
		color: var(--color-heading);
	}

	.customer-quote__party-line {
		margin: 0;
		color: var(--color-text--secondary);
	}

	.customer-quote__intro,
	.customer-quote__copy {
		margin: 0;
		white-space: pre-wrap;
		line-height: var(--typography--lineHeight-large);
	}

	.customer-quote__table-wrap {
		overflow-x: auto;
	}

	.customer-quote__table {
		width: 100%;
		border-collapse: collapse;
	}

	.customer-quote__table-caption {
		text-align: left;
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: var(--typography--letterSpacing-loose);
		color: var(--color-text--secondary);
		padding-bottom: var(--space-small);
	}

	.customer-quote__table th {
		text-align: left;
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
		font-weight: 600;
		padding: var(--space-small) var(--space-smaller);
		border-bottom: 1px solid var(--color-border);
	}

	.customer-quote__cell {
		padding: var(--space-base) var(--space-smaller);
		border-bottom: 1px solid var(--color-border);
		vertical-align: top;
	}

	.customer-quote__cell--number,
	th.customer-quote__cell--number {
		text-align: right;
		white-space: nowrap;
	}

	.customer-quote__row--group th,
	.customer-quote__row--heading th {
		padding-top: var(--space-large);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		border-bottom: 1px solid var(--color-border);
	}

	.customer-quote__group-name {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
		font-weight: 700;
	}

	.customer-quote__group-description {
		display: block;
		font-weight: 400;
		color: var(--color-text--secondary);
	}

	.customer-quote__item {
		display: flex;
		gap: var(--space-base);
	}

	.customer-quote__thumb {
		width: 56px;
		height: 56px;
		object-fit: cover;
		border-radius: var(--radius-base);
		border: 1px solid var(--color-border);
	}

	.customer-quote__item-name {
		margin: 0;
		font-weight: 600;
		color: var(--color-heading);
	}

	.customer-quote__item-description {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text--secondary);
		white-space: pre-wrap;
	}

	.customer-quote__item-tag {
		margin: var(--space-smallest) 0 0;
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.customer-quote__totals {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0 0 0 auto;
		width: min(320px, 100%);
	}

	.customer-quote__total-row {
		display: flex;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.customer-quote__total-row dt {
		color: var(--color-text--secondary);
	}

	.customer-quote__total-row dd {
		margin: 0;
		font-weight: 600;
		color: var(--color-heading);
	}

	.customer-quote__total-row--grand {
		padding-top: var(--space-small);
		border-top: 1px solid var(--color-border);
		font-size: var(--typography--fontSize-large);
	}

	.customer-quote__total-rate {
		color: var(--color-text--secondary);
	}

	.customer-quote__block-title {
		margin: 0 0 var(--space-small);
		font-size: var(--typography--fontSize-large);
		font-weight: 700;
		color: var(--color-heading);
	}

	.customer-quote__files {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}

	.customer-quote__file {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		padding: var(--space-small);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-base);
		text-decoration: none;
		color: inherit;

		&:hover {
			border-color: var(--color-interactive);
			background: var(--color-surface--background);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.customer-quote__file-thumb {
		width: 40px;
		height: 40px;
		object-fit: cover;
		border-radius: var(--radius-base);
	}

	.customer-quote__file-icon :global(svg),
	.customer-quote__file-download :global(svg) {
		width: 20px;
		height: 20px;
		color: var(--color-text--secondary);
	}

	.customer-quote__file-text {
		display: flex;
		flex-direction: column;
		margin-right: auto;
	}

	.customer-quote__file-name {
		font-weight: 600;
		color: var(--color-heading);
	}

	.customer-quote__file-size {
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.customer-quote__disclaimer {
		padding-top: var(--space-base);
		border-top: 1px solid var(--color-border);
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
		white-space: pre-wrap;
	}

	.customer-quote__disclaimer p {
		margin: 0;
	}

	.customer-quote__rail-card {
		position: sticky;
		top: var(--space-large);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		padding: var(--space-large);
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.customer-quote__rail-label {
		margin: 0;
		font-size: var(--typography--fontSize-small);
		text-transform: uppercase;
		letter-spacing: var(--typography--letterSpacing-loose);
		color: var(--color-text--secondary);
	}

	.customer-quote__rail-total {
		margin: 0;
		font-size: var(--typography--fontSize-jumbo);
		line-height: var(--typography--lineHeight-minuscule);
		font-weight: 900;
		color: var(--color-heading);
	}

	.customer-quote__deposit {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		padding-top: var(--space-base);
		border-top: 1px solid var(--color-border);
	}

	.customer-quote__deposit-amount {
		margin: 0;
		font-size: var(--typography--fontSize-large);
		font-weight: 700;
		color: var(--color-heading);
	}

	.customer-quote__deposit-note {
		margin: 0;
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.customer-quote__decisions {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}

	.customer-quote__decision {
		width: 100%;
		padding: var(--space-base);
		border-radius: var(--radius-base);
		border: 1px solid transparent;
		background: var(--color-interactive);
		color: var(--color-surface);
		font-weight: 600;
		font-size: var(--typography--fontSize-base);

		&:disabled {
			background: var(--color-disabled--secondary);
			color: var(--color-disabled);
			cursor: not-allowed;
		}
	}

	.customer-quote__decision--secondary {
		background: transparent;
		border-color: var(--color-border);
		color: var(--color-text);

		&:disabled {
			background: transparent;
			color: var(--color-disabled);
		}
	}

	// On a phone the document keeps its shape and loses its margins: the paper is the screen.
	@media (max-width: 640px) {
		.customer-quote__grid {
			padding: var(--space-base);
		}

		.customer-quote__paper {
			padding: var(--space-large);
			gap: var(--space-base);
		}

		.customer-quote__totals {
			width: 100%;
		}

		.customer-quote__rail-card {
			position: static;
		}
	}

	.customer-quote__decision-note {
		margin: 0;
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
		text-align: center;
	}

	.customer-quote__decision-question {
		margin: 0;
		font-weight: 600;
		color: var(--color-heading);
	}

	// The pad sits in a narrow rail, so its own row wraps rather than squeezing the name field down to
	// nothing beside the Clear button.
	.customer-quote__decision-signature {
		margin-bottom: var(--space-small);

		:global(.signature-pad__row) {
			flex-wrap: wrap;
		}

		:global(.signature-pad__canvas) {
			height: 120px;
		}
	}

	.customer-quote__decision-field {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);

		textarea {
			width: 100%;
			padding: var(--space-small);
			border: 1px solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			color: var(--color-text);
			font-family: inherit;
			font-size: var(--typography--fontSize-base);
			resize: vertical;

			&:focus-visible {
				outline: none;
				border-color: var(--color-interactive);
				box-shadow: var(--shadow-focus);
			}
		}
	}

	.customer-quote__decision-problem {
		margin: 0;
		font-size: var(--typography--fontSize-small);
		color: var(--color-critical);
	}

	.customer-quote__decision-done {
		margin: 0;
		font-weight: 600;
		color: var(--color-heading);
		text-align: center;
	}

	// On paper there is no app and no decision to make: what is left is the document, in ink that a
	// printer can actually reproduce, whichever theme the screen was using.
	@media print {
		.customer-quote {
			min-height: 0;
			background: #fff;
			color: #000;
		}

		.customer-quote__brand,
		.customer-quote__notice,
		.customer-quote__rail,
		.customer-quote__file-download {
			display: none;
		}

		.customer-quote__grid {
			display: block;
			max-width: none;
			padding: 0;
		}

		.customer-quote__paper {
			border: 0;
			border-radius: 0;
			padding: 0;
			gap: 16px;
		}

		.customer-quote__title,
		.customer-quote__fact dd,
		.customer-quote__party-name,
		.customer-quote__item-name,
		.customer-quote__total-row dd,
		.customer-quote__block-title,
		.customer-quote__file-name {
			color: #000;
		}

		.customer-quote__fact dt,
		.customer-quote__party-title,
		.customer-quote__party-line,
		.customer-quote__item-description,
		.customer-quote__total-row dt,
		.customer-quote__disclaimer,
		.customer-quote__table th,
		.customer-quote__file-size,
		.customer-quote__group-description {
			color: #333;
		}

		.customer-quote__row,
		.customer-quote__block {
			break-inside: avoid;
		}

		.customer-quote__table {
			width: 100%;
		}
	}
</style>
