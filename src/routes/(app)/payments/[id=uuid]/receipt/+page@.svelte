<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import CustomerPaymentReceiptDocument from '$lib/components/invoices/CustomerPaymentReceiptDocument.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import printIcon from '@tabler/icons/outline/printer.svg?raw';
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';

	// The customer's receipt, opened by staff in a new tab. It deliberately breaks out of the app shell: with
	// our sidebar around it, nobody can tell what is the document and what is our software.
	//
	// The strip along the top is the only thing on this page that is not the customer's receipt, and it
	// disappears when the page is printed.
	let { data } = $props();

	// `Print or save PDF` opens this page with `?print=1`, so one press gets a print dialog instead of a page
	// and then a second instruction.
	onMount(() => {
		if (page.url.searchParams.get('print') === '1') window.print();
	});
</script>

<svelte:head>
	<title>Payment receipt</title>
	<meta name="robots" content="noindex, nofollow" />
</svelte:head>

<CustomerPaymentReceiptDocument doc={data.document}>
	{#snippet notice()}
		<div class="preview-bar">
			<span class="preview-bar__icon" aria-hidden="true">{@html eyeIcon}</span>
			<div class="preview-bar__text">
				<p class="preview-bar__title">This is your customer's receipt</p>
				<p class="preview-bar__detail">
					This is exactly what your customer sees when they open the receipt you emailed them.
				</p>
			</div>
			<Button variant="secondary" onclick={() => window.print()}>
				{@html printIcon}
				Print or save PDF
			</Button>
		</div>
	{/snippet}
</CustomerPaymentReceiptDocument>

<style lang="scss">
	.preview-bar {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		padding: var(--space-base);
		background: var(--color-informative--surface);
		border: 1px solid var(--color-informative);
		border-radius: var(--radius-large);
	}

	.preview-bar__icon :global(svg) {
		width: 20px;
		height: 20px;
		color: var(--color-informative--onSurface);
	}

	.preview-bar__text {
		margin-right: auto;
	}

	.preview-bar__title {
		margin: 0;
		font-weight: 700;
		color: var(--color-informative--onSurface);
	}

	.preview-bar__detail {
		margin: 0;
		font-size: var(--typography--fontSize-small);
		color: var(--color-informative--onSurface);
	}

	@media (max-width: 640px) {
		.preview-bar {
			flex-wrap: wrap;
		}
	}
</style>
