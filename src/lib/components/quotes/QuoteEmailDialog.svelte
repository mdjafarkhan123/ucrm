<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import { queueQuoteEmail, type QuoteDetail, type QuoteWriteError } from '$lib/quotes/api';

	let {
		open,
		quoteId,
		quote,
		onClose,
		onQueued
	}: {
		open: boolean;
		quoteId: string;
		quote: QuoteDetail;
		onClose: () => void;
		onQueued: () => Promise<void> | void;
	} = $props();

	let queueing = $state(false);
	let error = $state('');

	const recipient = $derived(quote.quote.client?.email ?? null);
	const organizationName = $derived(quote.version?.organization_name ?? 'your business');

	function close() {
		if (queueing) return;
		error = '';
		onClose();
	}

	async function queue() {
		if (queueing || !recipient) return;
		queueing = true;
		error = '';
		try {
			await queueQuoteEmail(quoteId, crypto.randomUUID());
			await onQueued();
			error = '';
			onClose();
		} catch (exception) {
			const failure = exception as QuoteWriteError;
			error =
				failure.fieldErrors?.form ?? failure.message ?? 'The quote email could not be queued.';
		} finally {
			queueing = false;
		}
	}
</script>

<Dialog {open} title="Preview quote email" size="default" onClose={close}>
	<div class="quote-email">
		<dl class="quote-email__details">
			<div>
				<dt>To</dt>
				<dd>{recipient ?? 'No active customer email address'}</dd>
			</div>
			<div>
				<dt>From</dt>
				<dd>Your eligible email identity</dd>
			</div>
			<div>
				<dt>Subject</dt>
				<dd>Your quote from {organizationName}</dd>
			</div>
		</dl>

		<div class="quote-email__message">
			<p>Your quote is ready to review.</p>
			<span class="quote-email__link" aria-label="View your quote button preview"
				>View your quote</span
			>
			<p class="quote-email__fallback">
				A secure fallback link is included in the delivered email.
			</p>
		</div>

		<p class="quote-email__notice">
			UCRM checks the quote, recipient, sender, and allowance again before queueing. Delivery is
			still disabled, so a queued email will not be sent yet.
		</p>
		{#if error}<p class="quote-email__error" role="alert">{error}</p>{/if}
		{#if !recipient}
			<p class="quote-email__error" role="alert">
				Add an active email address to this customer before sending the quote.
			</p>
		{/if}

		<footer class="quote-email__footer">
			<Button variant="secondary" onclick={close} disabled={queueing}>Cancel</Button>
			<Button
				variant="primary"
				onclick={() => void queue()}
				disabled={!recipient}
				loading={queueing}>Queue email</Button
			>
		</footer>
	</div>
</Dialog>

<style lang="scss">
	:global(.quote-email) {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	:global(.quote-email__details) {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}

	:global(.quote-email__details div) {
		display: grid;
		grid-template-columns: 72px minmax(0, 1fr);
		gap: var(--space-small);
	}

	:global(.quote-email__details dt) {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	:global(.quote-email__details dd) {
		min-width: 0;
		color: var(--color-heading);
		font-weight: 600;
		overflow-wrap: anywhere;
	}

	:global(.quote-email__message) {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-text);
	}

	:global(.quote-email__link) {
		display: inline-flex;
		align-items: center;
		min-height: 40px;
		padding: 0 var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-surface);
		background: var(--color-interactive);
		font-weight: 600;
	}

	:global(.quote-email__fallback),
	:global(.quote-email__notice) {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	:global(.quote-email__notice) {
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-informative--surface);
	}

	:global(.quote-email__error) {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	:global(.quote-email__footer) {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
		margin-top: var(--space-small);
	}
</style>
