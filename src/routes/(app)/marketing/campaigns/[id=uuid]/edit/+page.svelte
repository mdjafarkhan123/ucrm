<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import CampaignJourney from '$lib/components/marketing/CampaignJourney.svelte';
	import { fetchCampaign, marketingCampaignKey, type MarketingApiError } from '$lib/marketing/api';

	const campaignId = $derived(page.params.id ?? '');
	const query = createQuery(() => ({
		queryKey: marketingCampaignKey(campaignId),
		queryFn: () => fetchCampaign(campaignId)
	}));

	const notFound = $derived((query.error as MarketingApiError | null)?.status === 404);
	const campaignsHref = resolve('/(app)/marketing') + '?tab=campaigns';
</script>

<PageContainer variant="fill">
	{#if query.isPending}
		<div class="campaign-edit-loading">
			<LoadingSkeleton variant="card" rows={4} label="Loading campaign draft" />
		</div>
	{:else if notFound}
		<EmptyState title="That campaign no longer exists" description="It may have been deleted.">
			{#snippet action()}
				<Button href={campaignsHref}>Back to campaigns</Button>
			{/snippet}
		</EmptyState>
	{:else if query.isError}
		<ErrorState
			title="This campaign could not be loaded"
			description="Something went wrong on our side. Try again."
			retry={() => query.refetch()}
		/>
	{:else if query.data.status !== 'draft'}
		<EmptyState
			title="This campaign can no longer be edited"
			description="Only a draft campaign can be changed. Duplicate it from the Campaigns list to reuse its content."
		>
			{#snippet action()}
				<Button href={campaignsHref}>Back to campaigns</Button>
			{/snippet}
		</EmptyState>
	{:else}
		<CampaignJourney initial={query.data} />
	{/if}
</PageContainer>

<style lang="scss">
	.campaign-edit-loading {
		max-width: 1040px;
		margin-inline: auto;
		padding-block: var(--space-large);
		padding-inline: var(--space-base);
	}
</style>
