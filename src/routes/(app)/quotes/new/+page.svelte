<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { createQuery } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import QuoteForm from '$lib/components/quotes/QuoteForm.svelte';
	import { fetchQuoteOverview, quoteCountsKey } from '$lib/quotes/api';

	// The organization's money format, so the line editor and the Overview card write figures the same way
	// the Quotes list does. Coming from that list it is already cached, so nothing waits on it.
	const overviewQuery = createQuery(() => ({
		queryKey: quoteCountsKey,
		queryFn: fetchQuoteOverview,
		staleTime: 60_000
	}));

	function handleSaved(quote: { id: string; number: number }) {
		void goto(resolve('/(app)/quotes/[id]', { id: quote.id }));
	}
</script>

<svelte:head><title>New quote · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<QuoteForm
		currencyCode={overviewQuery.data?.currency_code ?? 'USD'}
		locale={overviewQuery.data?.locale ?? 'en-US'}
		onSaved={handleSaved}
		onCancel={() => goto(resolve('/(app)/quotes'))}
	/>
</PageContainer>
