<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import CustomerJobReportDocument from '$lib/components/jobs/CustomerJobReportDocument.svelte';
	import printIcon from '@tabler/icons/outline/printer.svg?raw';
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';

	// What the client sees, opened by staff in a new tab. It deliberately breaks out of the app shell: with
	// our sidebar around it, nobody can tell what is the document and what is our software.
	let { data } = $props();

	const doc = $derived(data.preview.document);
	const info = $derived(data.preview.preview);

	function fileHref(attachmentId: string) {
		return `/api/attachments/${attachmentId}/view`;
	}

	// `Print or save PDF` opens this page with `?print=1`, so one press gets a print dialog instead of a page
	// and then a second instruction.
	onMount(() => {
		if (page.url.searchParams.get('print') === '1') window.print();
	});
</script>

<svelte:head>
	<title>{doc ? `Preview work report — job #${doc.job.job_number}` : 'Preview work report'}</title>
	<meta name="robots" content="noindex, nofollow" />
</svelte:head>

{#if doc}
	<CustomerJobReportDocument {doc} {fileHref}>
		{#snippet notice()}
			<div class="preview-bar">
				<span class="preview-bar__icon" aria-hidden="true">{@html eyeIcon}</span>
				<div class="preview-bar__text">
					<p class="preview-bar__title">This is your client's view</p>
					<p class="preview-bar__detail">
						This is exactly how your client sees this report.
						{#if info.prices_withheld}
							Amounts are left out because you do not have access to them — your client still sees
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
	</CustomerJobReportDocument>
{:else}
	<main class="preview-empty">
		<h1>Nothing to preview yet</h1>
		<p>
			Add photos, checklist answers or a summary to this job's work report before previewing it.
		</p>
	</main>
{/if}

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

	.preview-empty {
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

	.preview-empty h1 {
		margin: 0;
		font-size: var(--typography--fontSize-largest);
		font-weight: 700;
		color: var(--color-heading);
	}

	.preview-empty p {
		margin: 0;
		max-width: 44ch;
		color: var(--color-text--secondary);
	}
</style>
