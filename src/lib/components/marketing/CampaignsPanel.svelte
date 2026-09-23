<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import { goto } from '$app/navigation';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		fetchCampaigns,
		fetchCustomerGroups,
		deleteCampaignRequest,
		cancelCampaignRequest,
		marketingCampaignsKey,
		marketingCustomerGroupsKey
	} from '$lib/marketing/api';
	import {
		marketingGoalLabels,
		marketingCampaignStatusLabels,
		marketingCampaignStatusTones,
		type MarketingCampaignListItem
	} from '$lib/marketing/campaign-content';
	import speakerphoneIcon from '@tabler/icons/outline/speakerphone.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import banIcon from '@tabler/icons/outline/ban.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const campaignsQuery = createQuery(() => ({
		queryKey: marketingCampaignsKey,
		queryFn: fetchCampaigns
	}));
	// Only used to show a group's name next to its id -- Customer groups already owns loading and editing
	// the list itself, so a small org's worth of groups is fetched again here rather than threaded through
	// from a sibling tab that may never have been opened.
	const groupsQuery = createQuery(() => ({
		queryKey: marketingCustomerGroupsKey,
		queryFn: fetchCustomerGroups
	}));

	const groupNames = $derived(
		new Map((groupsQuery.data ?? []).map((group) => [group.id, group.name]))
	);

	let deleteTarget = $state<MarketingCampaignListItem | null>(null);
	let deleting = $state(false);
	let cancelTarget = $state<MarketingCampaignListItem | null>(null);
	let cancelling = $state(false);

	function editHref(campaign: MarketingCampaignListItem): string {
		return resolve('/(app)/marketing/campaigns/[id=uuid]/edit', { id: campaign.id });
	}
	function detailHref(campaign: MarketingCampaignListItem): string {
		return resolve('/(app)/marketing/campaigns/[id=uuid]', { id: campaign.id });
	}
	function openHref(campaign: MarketingCampaignListItem): string {
		return campaign.status === 'draft' ? editHref(campaign) : detailHref(campaign);
	}

	function menuItems(campaign: MarketingCampaignListItem) {
		if (campaign.status === 'draft') {
			return [
				{ label: 'Edit', icon: pencilIcon, onSelect: () => void goto(editHref(campaign)) },
				{
					label: 'Delete',
					icon: trashIcon,
					destructive: true,
					onSelect: () => (deleteTarget = campaign)
				}
			];
		}
		if (campaign.status === 'scheduled' || campaign.status === 'sending') {
			return [
				{
					label: 'Cancel campaign',
					icon: banIcon,
					destructive: true,
					onSelect: () => (cancelTarget = campaign)
				}
			];
		}
		return [];
	}

	async function confirmDelete() {
		if (!deleteTarget) return;
		deleting = true;
		try {
			await deleteCampaignRequest(deleteTarget.id);
			deleteTarget = null;
			await queryClient.invalidateQueries({ queryKey: marketingCampaignsKey });
			toast.success('Campaign deleted.');
		} catch (cause) {
			toast.error(cause instanceof Error ? cause.message : 'That campaign could not be deleted.');
		} finally {
			deleting = false;
		}
	}

	async function confirmCancel() {
		if (!cancelTarget) return;
		cancelling = true;
		try {
			await cancelCampaignRequest(cancelTarget.id);
			cancelTarget = null;
			await queryClient.invalidateQueries({ queryKey: marketingCampaignsKey });
			toast.success('Campaign cancelled.');
		} catch (cause) {
			toast.error(cause instanceof Error ? cause.message : 'That campaign could not be cancelled.');
		} finally {
			cancelling = false;
		}
	}

	const columns: DataTableColumn[] = [
		{ key: 'name', label: 'Name' },
		{ key: 'goal', label: 'Goal' },
		{ key: 'status', label: 'Status' },
		{ key: 'customer_group', label: 'Customer group' },
		{ key: 'updated_at', label: 'Last updated' }
	];

	const dateFormatter = new Intl.DateTimeFormat('en-US', { dateStyle: 'medium' });
	const newCampaignHref = resolve('/(app)/marketing/campaigns/new');
</script>

<SectionBlock
	title="Campaigns"
	hint="Draft, save, and send one-off marketing email to the customers you choose."
	level={2}
>
	{#snippet actions()}
		<Button size="small" href={newCampaignHref}>New campaign</Button>
	{/snippet}

	{#if campaignsQuery.isPending}
		<LoadingSkeleton variant="table" rows={3} label="Loading campaigns" />
	{:else if campaignsQuery.isError}
		<ErrorState
			description="Campaigns could not be loaded."
			retry={() => campaignsQuery.refetch()}
		/>
	{:else if campaignsQuery.data.length === 0}
		<EmptyState
			icon={speakerphoneIcon}
			title="No campaigns yet"
			description="Start from a goal, choose who to email, and build the message — all in one guided flow."
		>
			{#snippet action()}
				<Button variant="secondary" href={newCampaignHref}>New campaign</Button>
			{/snippet}
		</EmptyState>
	{:else}
		<DataTable
			{columns}
			items={campaignsQuery.data}
			rowId={(campaign) => campaign.id}
			caption="Campaigns"
			onRowActivate={(campaign) => void goto(openHref(campaign))}
		>
			{#snippet row(campaign: MarketingCampaignListItem)}
				<th scope="row">
					<a href={openHref(campaign)}>{campaign.name}</a>
				</th>
				<td>{marketingGoalLabels[campaign.goal]}</td>
				<td>
					<StatusBadge status={marketingCampaignStatusTones[campaign.status]}>
						{marketingCampaignStatusLabels[campaign.status]}
					</StatusBadge>
				</td>
				<td>
					{campaign.customer_group_id ? (groupNames.get(campaign.customer_group_id) ?? '—') : '—'}
				</td>
				<td>{dateFormatter.format(new Date(campaign.updated_at))}</td>
			{/snippet}
			{#snippet rowActions(campaign: MarketingCampaignListItem)}
				{#if menuItems(campaign).length > 0}
					<DropdownMenu triggerLabel={`Actions for ${campaign.name}`} items={menuItems(campaign)} />
				{/if}
			{/snippet}
		</DataTable>
	{/if}
</SectionBlock>

<ConfirmDialog
	open={deleteTarget !== null}
	title="Delete this campaign?"
	tone="critical"
	destructive
	confirmLabel="Delete campaign"
	cancelLabel="Keep it"
	loading={deleting}
	onConfirm={() => void confirmDelete()}
	onClose={() => (deleteTarget = null)}
>
	<p>This can't be undone. "{deleteTarget?.name}" and its draft content will be removed.</p>
</ConfirmDialog>

<ConfirmDialog
	open={cancelTarget !== null}
	title="Cancel this campaign?"
	tone="critical"
	destructive
	confirmLabel="Cancel campaign"
	cancelLabel="Keep sending"
	loading={cancelling}
	onConfirm={() => void confirmCancel()}
	onClose={() => (cancelTarget = null)}
>
	<p>
		Sent email cannot be recalled. Cancelling "{cancelTarget?.name}" only stops recipients who
		haven't been sent to yet.
	</p>
</ConfirmDialog>
