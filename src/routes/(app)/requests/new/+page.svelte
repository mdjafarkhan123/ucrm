<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { createQuery } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import RequestForm from '$lib/components/requests/RequestForm.svelte';
	import { fetchQuoteOverview, quoteCountsKey } from '$lib/quotes/api';
	import checkIcon from '@tabler/icons/outline/circle-check.svg?raw';

	// The organization's money format, so the line items on this page write figures the same way the quote
	// they turn into will. It is one row for the whole tenant and it is cached, so nothing waits on it.
	const overviewQuery = createQuery(() => ({
		queryKey: quoteCountsKey,
		queryFn: fetchQuoteOverview,
		staleTime: 60_000
	}));

	let savedMessage = $state('');
	// Remounts the form for "Save & create another" so every field and attachment starts clean.
	let formKey = $state(0);

	function handleSaved(request: { id: string; title: string }, andAnother: boolean) {
		if (andAnother) {
			savedMessage = `${request.title} was saved. Here is a fresh form.`;
			formKey += 1;
			return;
		}
		// The path is resolved; the rule just cannot see through the appended query string that carries
		// the confirmation across to the request's page.
		// eslint-disable-next-line svelte/no-navigation-without-resolve
		void goto(`${resolve('/(app)/requests/[id]', { id: request.id })}?saved=1`);
	}
</script>

<svelte:head><title>New request · Contractor CRM</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<PageContainer variant="fill">
	{#if savedMessage}
		<p class="request-new__saved" role="status">
			<span aria-hidden="true">{@html checkIcon}</span>{savedMessage}
		</p>
	{/if}

	{#key formKey}
		<RequestForm
			currencyCode={overviewQuery.data?.currency_code ?? 'USD'}
			locale={overviewQuery.data?.locale ?? 'en-US'}
			onSaved={handleSaved}
			onCancel={() => goto(resolve('/(app)/requests'))}
		/>
	{/key}
</PageContainer>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.request-new__saved {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin-bottom: var(--space-base);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
		font-size: var(--typography--fontSize-small);

		:global(svg) {
			display: block;
			width: 18px;
			height: 18px;
		}
	}
</style>
