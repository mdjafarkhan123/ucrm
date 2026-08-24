<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import CustomerQuoteDocument from '$lib/components/quotes/CustomerQuoteDocument.svelte';
	import printIcon from '@tabler/icons/outline/printer.svg?raw';
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';

	// What the client sees, opened by staff in a new tab. It deliberately breaks out of the app shell:
	// with our sidebar around it, nobody can tell what is the document and what is our software.
	//
	// The strip along the top is the only thing on this page that is not the client's document, and it
	// disappears when the page is printed.
	let { data } = $props();

	const doc = $derived(data.preview.document);
	const info = $derived(data.preview.preview);

	function fileHref(attachmentId: string, size?: 'thumb') {
		return size
			? `/api/attachments/${attachmentId}/view?size=${size}`
			: `/api/attachments/${attachmentId}/download`;
	}

	// `Print or save PDF` in the quote menu opens this page with `?print=1`, so one menu press gets a
	// print dialog instead of a page and then a second instruction.
	onMount(() => {
		if (page.url.searchParams.get('print') === '1') window.print();
	});
</script>

<svelte:head>
	<title>Preview quote #{doc.quote.quote_number}</title>
	<meta name="robots" content="noindex, nofollow" />
</svelte:head>

<CustomerQuoteDocument {doc} decisions="inert" {fileHref}>
	{#snippet notice()}
		<div class="preview-bar">
			<span class="preview-bar__icon" aria-hidden="true">{@html eyeIcon}</span>
			<div class="preview-bar__text">
				<p class="preview-bar__title">This is your client's view</p>
				<p class="preview-bar__detail">
					{#if info.version_status === 'draft'}
						Nothing has been sent yet. This is how your client will see it once you do.
					{:else}
						Version {info.version_number}, the one your client can see right now.
					{/if}
					{#if info.prices_withheld}
						Prices are left out because you do not have access to them — your client still sees
						them.
					{/if}
				</p>
			</div>
			<button class="preview-bar__print" type="button" onclick={() => window.print()}>
				<span aria-hidden="true">{@html printIcon}</span>
				Print or save PDF
			</button>
		</div>
	{/snippet}
</CustomerQuoteDocument>

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

	.preview-bar__print {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
		border: 1px solid var(--color-border);
		background: var(--color-surface);
		color: var(--color-text);
		font-weight: 600;
		white-space: nowrap;

		&:hover {
			border-color: var(--color-interactive);
			color: var(--color-interactive);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.preview-bar__print :global(svg) {
		width: 18px;
		height: 18px;
	}

	@media (max-width: 640px) {
		.preview-bar {
			flex-wrap: wrap;
		}
	}
</style>
