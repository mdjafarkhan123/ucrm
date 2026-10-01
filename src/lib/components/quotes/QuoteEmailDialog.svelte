<script lang="ts">
	import QuoteEmailPreview from './QuoteEmailPreview.svelte';
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
			error = failure.fieldErrors?.form ?? failure.message ?? 'The quote email could not be sent.';
		} finally {
			queueing = false;
		}
	}
</script>

<Dialog {open} title="Email this quote" size="default" onClose={close}>
	<div class="quote-email">
		<QuoteEmailPreview {recipient} {organizationName} />

		<p class="quote-email__notice">
			UCRM checks the quote, recipient, and sender again, then sends it. If the email does not reach
			the customer, this quote will say so.
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
				loading={queueing}>Send email</Button
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

	:global(.quote-email__notice) {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
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
