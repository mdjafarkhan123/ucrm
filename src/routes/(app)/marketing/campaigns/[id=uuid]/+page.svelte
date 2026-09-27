<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import { urlParam } from '$lib/url-param.svelte';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Tabs, { type Tab } from '$lib/components/ui/Tabs.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import MarketingTemplatePreview from '$lib/components/marketing/MarketingTemplatePreview.svelte';
	import CampaignRecipientsPanel from '$lib/components/marketing/CampaignRecipientsPanel.svelte';
	import CampaignResultsPanel from '$lib/components/marketing/CampaignResultsPanel.svelte';
	import {
		cancelCampaignRequest,
		fetchCampaignAttributionCandidates,
		fetchCampaignOverview,
		fetchCampaignRecipients,
		fetchCampaignResults,
		type MarketingApiError
	} from '$lib/marketing/api';
	import {
		marketingCampaignAttributionCandidatesKey,
		marketingCampaignOverviewKey,
		marketingCampaignRecipientsKey,
		marketingCampaignResultsKey,
		marketingCampaignsKey,
		marketingGoalLabels,
		marketingCampaignStatusLabels,
		marketingCampaignStatusTones
	} from '$lib/marketing/campaign-content';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import banIcon from '@tabler/icons/outline/ban.svg?raw';

	// The read-first campaign detail page (blueprint §12): a launched campaign has nothing left to edit here,
	// only to review -- unlike the draft editor at .../edit, this page never stages a change.
	const campaignId = $derived(page.params.id ?? '');
	const queryClient = useQueryClient();
	const toast = getToastManager();

	const overviewQuery = createQuery(() => ({
		queryKey: marketingCampaignOverviewKey(campaignId),
		queryFn: () => fetchCampaignOverview(campaignId)
	}));

	const notFound = $derived((overviewQuery.error as MarketingApiError | null)?.status === 404);
	const campaignsHref = resolve('/(app)/marketing') + '?tab=campaigns';
	const editHref = $derived(
		resolve('/(app)/marketing/campaigns/[id=uuid]/edit', { id: campaignId })
	);

	// Tabs. Overview is the default and loads with the page; each other tab's query stays off until it is
	// actually open (CLAUDE.md rule 9) -- `onhover` warms the exact cache key its panel reads, so the click
	// that follows finds it ready.
	const campaignTabs: Tab[] = [
		{ value: 'overview', label: 'Overview' },
		{
			value: 'recipients',
			label: 'Recipients',
			onhover: () =>
				void queryClient.prefetchInfiniteQuery({
					queryKey: marketingCampaignRecipientsKey(campaignId, { statusFilter: '', search: '' }),
					queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
						fetchCampaignRecipients(campaignId, { statusFilter: '', search: '' }, pageParam),
					initialPageParam: undefined as string | undefined
				})
		},
		{ value: 'content', label: 'Content' },
		{
			value: 'results',
			label: 'Results',
			onhover: () => {
				void queryClient.prefetchQuery({
					queryKey: marketingCampaignResultsKey(campaignId),
					queryFn: () => fetchCampaignResults(campaignId)
				});
				void queryClient.prefetchQuery({
					queryKey: marketingCampaignAttributionCandidatesKey(campaignId),
					queryFn: () => fetchCampaignAttributionCandidates(campaignId)
				});
			}
		}
	];

	const tabParam = urlParam('tab', 'overview');
	const activeTab = $derived(
		campaignTabs.some((tab) => tab.value === tabParam.current) ? tabParam.current : 'overview'
	);
	const selectTab = tabParam.set;

	let cancelling = $state(false);
	let cancelOpen = $state(false);
	async function confirmCancel() {
		cancelling = true;
		try {
			await cancelCampaignRequest(campaignId);
			cancelOpen = false;
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: marketingCampaignOverviewKey(campaignId) }),
				queryClient.invalidateQueries({ queryKey: marketingCampaignsKey })
			]);
			toast.success('Campaign cancelled.');
		} catch (cause) {
			toast.error(cause instanceof Error ? cause.message : 'That campaign could not be cancelled.');
		} finally {
			cancelling = false;
		}
	}

	const dateTimeFormat = new Intl.DateTimeFormat('en-US', {
		dateStyle: 'medium',
		timeStyle: 'short'
	});
	function formatWhen(value: string | null) {
		return value ? dateTimeFormat.format(new Date(value)) : '—';
	}
</script>

<svelte:head><title>Campaign · Marketing · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	{#if overviewQuery.isPending}
		<LoadingSkeleton variant="card" rows={4} label="Loading campaign" />
	{:else if notFound}
		<EmptyState title="That campaign no longer exists" description="It may have been deleted.">
			{#snippet action()}
				<Button href={campaignsHref}>Back to campaigns</Button>
			{/snippet}
		</EmptyState>
	{:else if overviewQuery.isError}
		<ErrorState
			title="This campaign could not be loaded"
			description="Something went wrong on our side. Try again."
			retry={() => overviewQuery.refetch()}
		/>
	{:else}
		{@const campaign = overviewQuery.data}
		<PageHeader
			eyebrow="Campaign"
			title={campaign.name}
			description={marketingGoalLabels[campaign.goal]}
		>
			{#snippet actions()}
				<StatusBadge status={marketingCampaignStatusTones[campaign.status]}>
					{marketingCampaignStatusLabels[campaign.status]}
				</StatusBadge>
				{#if campaign.status === 'draft'}
					<Button href={editHref}>Continue editing</Button>
				{:else if campaign.status === 'scheduled' || campaign.status === 'sending'}
					<Button variant="secondary" onclick={() => (cancelOpen = true)}>Cancel campaign</Button>
				{/if}
			{/snippet}
		</PageHeader>

		<Tabs tabs={campaignTabs} value={activeTab} onChange={selectTab} label="Campaign sections">
			<TabPanel value="overview">
				<div class="campaign-detail__stats">
					<KpiCard
						label="Waiting"
						value={String(campaign.counts.waiting)}
						note="Not yet submitted"
						icon={clockIcon}
						variant="compact"
					/>
					<KpiCard
						label="Submitted"
						value={String(campaign.counts.submitted)}
						note="Sent to the provider"
						icon={sendIcon}
						variant="compact"
					/>
					<KpiCard
						label="Delivered"
						value={String(campaign.counts.delivered)}
						note="Reached an inbox"
						icon={circleCheckIcon}
						variant="compact"
						tone="success"
					/>
					<KpiCard
						label="Failed / Excluded"
						value={String(campaign.counts.failed_excluded)}
						note="Bounced, complained, or never eligible"
						icon={alertTriangleIcon}
						variant="compact"
						tone="critical"
					/>
					<KpiCard
						label="Cancelled"
						value={String(campaign.counts.cancelled)}
						note="Stopped before sending"
						icon={banIcon}
						variant="compact"
					/>
				</div>

				<SectionBlock title="Details">
					<dl class="campaign-detail__facts">
						<div>
							<dt>Customer group</dt>
							<dd>{campaign.customer_group_name ?? '—'}</dd>
						</div>
						<div>
							<dt>Created</dt>
							<dd>{formatWhen(campaign.created_at)}</dd>
						</div>
						<div>
							<dt>{campaign.scheduled_for ? 'Scheduled for' : 'Launched'}</dt>
							<dd>{formatWhen(campaign.scheduled_for ?? campaign.launched_at)}</dd>
						</div>
						<div>
							<dt>Subject</dt>
							<dd>{campaign.content.subject || '—'}</dd>
						</div>
					</dl>
				</SectionBlock>
			</TabPanel>

			<TabPanel value="recipients">
				<CampaignRecipientsPanel {campaignId} active={activeTab === 'recipients'} />
			</TabPanel>

			<TabPanel value="content">
				{#if campaign.status === 'draft'}
					<EmptyState
						title="This campaign is still a draft"
						description="A draft has no frozen content yet -- continue editing it to see or change the message."
					>
						{#snippet action()}
							<Button href={editHref}>Continue editing</Button>
						{/snippet}
					</EmptyState>
				{:else if activeTab === 'content'}
					<MarketingTemplatePreview title={campaign.name} content={campaign.content} />
				{/if}
			</TabPanel>

			<TabPanel value="results">
				<CampaignResultsPanel {campaignId} active={activeTab === 'results'} />
			</TabPanel>
		</Tabs>
	{/if}
</PageContainer>

<ConfirmDialog
	open={cancelOpen}
	title="Cancel this campaign?"
	tone="critical"
	destructive
	confirmLabel="Cancel campaign"
	cancelLabel="Keep sending"
	loading={cancelling}
	onConfirm={() => void confirmCancel()}
	onClose={() => (cancelOpen = false)}
>
	<p>
		Sent email cannot be recalled. Cancelling only stops recipients who haven't been sent to yet.
	</p>
</ConfirmDialog>

<style lang="scss">
	.campaign-detail__stats {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
		gap: var(--space-base);
		margin-bottom: var(--space-large);
	}

	.campaign-detail__facts {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
		gap: var(--space-base);
		margin: 0;

		dt {
			margin: 0 0 2px;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		dd {
			margin: 0;
			color: var(--color-heading);
			font-weight: 600;
		}
	}
</style>
