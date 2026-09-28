<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ClientForm from '$lib/components/clients/ClientForm.svelte';
	import {
		clientDetailKey,
		fetchClient,
		type ClientDetail,
		type ClientReadError
	} from '$lib/clients/api';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';

	// The full edit page — Jobber's third edit pattern, opened in a new tab from the client page's ...
	// menu. Same cache entry as the client page, so it opens from memory when that page was just open.
	const clientId = $derived(page.params.id ?? '');
	const clientPage = $derived(resolve('/(app)/clients/[id=uuid]', { id: clientId }));

	const clientQuery = createQuery(() => ({
		queryKey: clientDetailKey(clientId),
		queryFn: () => fetchClient(clientId),
		enabled: Boolean(clientId)
	}));

	// Taken once the client first arrives. A background refetch must not remount the form mid-typing.
	let loaded = $state<ClientDetail>();
	$effect(() => {
		if (!loaded && clientQuery.data) loaded = clientQuery.data;
	});
</script>

<svelte:head>
	<title>Edit {loaded?.display_name ?? 'client'} · Contractor CRM</title>
</svelte:head>

<PageContainer variant="fill">
	{#if loaded}
		<ClientForm
			client={loaded}
			onSaved={() => goto(clientPage)}
			onCancel={() => goto(clientPage)}
		/>
	{:else if clientQuery.isPending}
		<LoadingSkeleton variant="card" label="Loading client" />
	{:else if (clientQuery.error as ClientReadError | null)?.status === 403}
		<EmptyState
			icon={lockIcon}
			title="You do not have access to this client"
			description="Ask an owner or admin if you need to edit it."
		/>
	{:else if (clientQuery.error as ClientReadError | null)?.status === 404}
		<EmptyState
			title="This client could not be found"
			description="It may have been deleted, or the link is out of date."
		/>
	{:else}
		<ErrorState
			description="That client could not be loaded. Try again."
			retry={() => clientQuery.refetch()}
		/>
	{/if}
</PageContainer>
