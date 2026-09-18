<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { createQuery } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import RequestForm from '$lib/components/requests/RequestForm.svelte';
	import { fetchQuoteOverview, quoteCountsKey } from '$lib/quotes/api';
	import { takeAssessmentSeed } from '$lib/requests/assessmentSeed';

	// The organization's money format, so the line items on this page write figures the same way the quote
	// they turn into will. It is one row for the whole tenant and it is cached, so nothing waits on it.
	const overviewQuery = createQuery(() => ({
		queryKey: quoteCountsKey,
		queryFn: fetchQuoteOverview,
		staleTime: 60_000
	}));

	// A slot may have been staged by Schedule's empty-slot chooser when the person picked Request. It is read
	// once, here on the way in, so the on-site assessment opens booked onto that slot; a plain New Request
	// reads nothing and opens with the empty visit card.
	const seed = takeAssessmentSeed();

	// Remounts the form for "Save & create another" so every field and attachment starts clean.
	let formKey = $state(0);

	function handleSaved(request: { id: string; title: string }, andAnother: boolean) {
		if (andAnother) {
			formKey += 1;
			return;
		}
		void goto(resolve('/(app)/requests/[id=uuid]', { id: request.id }));
	}
</script>

<svelte:head><title>New request · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	{#key formKey}
		<RequestForm
			currencyCode={overviewQuery.data?.currency_code ?? 'USD'}
			locale={overviewQuery.data?.locale ?? 'en-US'}
			timezone={overviewQuery.data?.timezone ?? 'UTC'}
			seed={formKey === 0 ? seed : null}
			onSaved={handleSaved}
			onCancel={() => goto(resolve('/(app)/requests'))}
		/>
	{/key}
</PageContainer>
