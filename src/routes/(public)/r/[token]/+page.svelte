<script lang="ts">
	import CustomerPaymentReceiptDocument from '$lib/components/invoices/CustomerPaymentReceiptDocument.svelte';

	// The customer's receipt page. Everything it draws came from the token in the URL, resolved on the server,
	// and it draws it with the same component staff will print from the payment screen — there is no second,
	// friendlier version of this document anywhere. Nothing is recorded from here.
	let { data } = $props();
</script>

<svelte:head>
	<title>{data.document ? 'Payment receipt' : 'Receipt not available'}</title>
	<meta name="robots" content="noindex, nofollow" />
	<meta name="referrer" content="no-referrer" />
</svelte:head>

{#if data.document}
	<CustomerPaymentReceiptDocument doc={data.document} />
{:else}
	<main class="receipt-unavailable">
		<h1>This receipt is not available</h1>
		<p>
			The link may have been replaced by a newer one, or it may have been turned off. Ask the
			company for an up-to-date link and they can send you another.
		</p>
	</main>
{/if}

<style lang="scss">
	.receipt-unavailable {
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
