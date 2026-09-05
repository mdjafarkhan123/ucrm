<script lang="ts">
	import CustomerInvoiceDocument from '$lib/components/invoices/CustomerInvoiceDocument.svelte';

	// The customer's page. Everything it draws came from the token in the URL, resolved on the server, and it
	// draws it with the same component staff see in Preview as client — there is no second, friendlier
	// version of this document anywhere.
	let { data } = $props();
</script>

<svelte:head>
	<title
		>{data.document
			? `Invoice #${data.document.invoice.invoice_number}`
			: data.expired
				? 'Link expired'
				: 'Invoice not available'}</title
	>
	<meta name="robots" content="noindex, nofollow" />
	<meta name="referrer" content="no-referrer" />
</svelte:head>

{#if data.document}
	<CustomerInvoiceDocument doc={data.document} />
{:else if data.expired}
	<main class="invoice-unavailable">
		<h1>This link has expired</h1>
		<p>
			Invoice links only stay open for a while. Ask the company for a fresh one and they can send
			you another straight away.
		</p>
	</main>
{:else}
	<main class="invoice-unavailable">
		<h1>This invoice is not available</h1>
		<p>
			The link may have been replaced by a newer one, or it may have been turned off. Ask the
			company for an up-to-date link and they can send you another.
		</p>
	</main>
{/if}

<style lang="scss">
	.invoice-unavailable {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		align-items: center;
		justify-content: center;
		min-height: 100vh;
		padding: var(--space-largest);
		text-align: center;
		background: var(--color-surface--background);
		color: var(--color-text);
	}

	h1 {
		margin: 0;
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
		font-weight: 700;
		color: var(--color-heading);
	}

	p {
		margin: 0;
		max-width: 44ch;
		color: var(--color-text--secondary);
	}
</style>
