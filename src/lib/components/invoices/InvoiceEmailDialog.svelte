<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';

	// The "Send invoice" confirmation. Presentational only: the page owns the send, because sending a draft
	// first issues it (issue_invoice, method 'sent') and only then delivers, and that lifecycle logic already
	// lives on the detail page next to Mark as Sent. This screen just shows who it goes to and asks.
	let {
		open,
		recipient,
		invoiceNumber,
		isDraft,
		sending,
		error,
		onClose,
		onConfirm
	}: {
		open: boolean;
		recipient: string | null;
		invoiceNumber: number;
		isDraft: boolean;
		sending: boolean;
		error: string;
		onClose: () => void;
		onConfirm: () => void;
	} = $props();

	function close() {
		if (sending) return;
		onClose();
	}
</script>

<Dialog {open} title="Send invoice" size="default" onClose={close}>
	<div class="invoice-email">
		<dl class="invoice-email__details">
			<div>
				<dt>To</dt>
				<dd>{recipient ?? 'No customer email address'}</dd>
			</div>
			<div>
				<dt>From</dt>
				<dd>Your eligible email identity</dd>
			</div>
			<div>
				<dt>Invoice</dt>
				<dd>#{invoiceNumber}</dd>
			</div>
		</dl>

		<div class="invoice-email__message">
			<p>We'll email your client a secure link to view and pay this invoice.</p>
			<span class="invoice-email__link" aria-label="View your invoice button preview"
				>View your invoice</span
			>
		</div>

		{#if isDraft}
			<p class="invoice-email__notice">
				Sending issues this invoice and freezes its document — it can't be edited after that, the
				same as Mark as Sent.
			</p>
		{/if}

		{#if error}<p class="invoice-email__error" role="alert">{error}</p>{/if}
		{#if !recipient}
			<p class="invoice-email__error" role="alert">
				Add an email address to this client before sending the invoice.
			</p>
		{/if}

		<footer class="invoice-email__footer">
			<Button variant="secondary" onclick={close} disabled={sending}>Cancel</Button>
			<Button variant="primary" onclick={onConfirm} disabled={!recipient} loading={sending}>
				{isDraft ? 'Send invoice' : 'Resend invoice'}
			</Button>
		</footer>
	</div>
</Dialog>

<style lang="scss">
	:global(.invoice-email) {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	:global(.invoice-email__details) {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}

	:global(.invoice-email__details div) {
		display: grid;
		grid-template-columns: 72px minmax(0, 1fr);
		gap: var(--space-small);
	}

	:global(.invoice-email__details dt) {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	:global(.invoice-email__details dd) {
		min-width: 0;
		color: var(--color-heading);
		font-weight: 600;
		overflow-wrap: anywhere;
	}

	:global(.invoice-email__message) {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-text);
	}

	:global(.invoice-email__link) {
		display: inline-flex;
		align-items: center;
		min-height: 40px;
		padding: 0 var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-surface);
		background: var(--color-interactive);
		font-weight: 600;
	}

	:global(.invoice-email__notice) {
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-informative--surface);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	:global(.invoice-email__error) {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	:global(.invoice-email__footer) {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
		margin-top: var(--space-small);
	}
</style>
