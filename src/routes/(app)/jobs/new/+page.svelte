<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { createQuery } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import JobForm from '$lib/components/jobs/JobForm.svelte';
	import { fetchJobOverview, jobCountsKey } from '$lib/jobs/api';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';

	// The organization's money format, so the line editor and the Job total card write figures the same way
	// the Jobs list does. Coming from that list it is already cached, so nothing waits on it.
	const overviewQuery = createQuery(() => ({
		queryKey: jobCountsKey,
		queryFn: fetchJobOverview,
		staleTime: 60_000
	}));

	const toast = getToastManager();

	function handleSaved(job: { id: string; number: number }) {
		// A new job lands on its own detail page, the way a saved quote does. The toast rides along through the
		// navigation to confirm it.
		toast.success(`Job #${job.number} created`);
		void goto(resolve('/(app)/jobs/[id]', { id: job.id }));
	}
</script>

<svelte:head><title>New job · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<JobForm
		currencyCode={overviewQuery.data?.currency_code ?? 'USD'}
		locale={overviewQuery.data?.locale ?? 'en-US'}
		onSaved={handleSaved}
		onCancel={() => goto(resolve('/(app)/jobs'))}
	/>
</PageContainer>
