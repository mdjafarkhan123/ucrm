<script lang="ts">
	import { createInfiniteQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { fetchCampaignRecipients } from '$lib/marketing/api';
	import {
		marketingCampaignRecipientsKey,
		marketingExcludedReasonLabels,
		marketingRecipientStatusLabels,
		marketingRecipientStatusTones,
		type MarketingCampaignRecipient,
		type MarketingCampaignRecipientFilter
	} from '$lib/marketing/campaign-content';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';

	// The Recipients tab (blueprint §12): a searchable, bounded, keyset-paginated list. Filters and search
	// live in the query key, so switching either resets to a fresh first page rather than trying to splice a
	// changed filter into pages already loaded under a different one.
	// `active` is only true once the parent page's Recipients tab is actually showing. bits-ui keeps every
	// TabPanel mounted (CSS-hidden), so the query stays off via `enabled` until then (CLAUDE.md rule 9) -- the
	// parent's Tabs `onhover` prefetches the same key with no filters, so the click that follows finds it warm.
	let { campaignId, active = false }: { campaignId: string; active?: boolean } = $props();

	let search = $state('');
	let debouncedSearch = $state('');
	let statusFilter = $state<MarketingCampaignRecipientFilter | ''>('');

	$effect(() => {
		const value = search;
		const handle = setTimeout(() => (debouncedSearch = value), 300);
		return () => clearTimeout(handle);
	});

	const filters = $derived({ statusFilter, search: debouncedSearch });

	const recipientsQuery = createInfiniteQuery(() => ({
		queryKey: marketingCampaignRecipientsKey(campaignId, filters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchCampaignRecipients(campaignId, filters, pageParam),
		initialPageParam: undefined as string | undefined,
		enabled: active,
		getNextPageParam: (lastPage) => lastPage.next_cursor ?? undefined
	}));

	const recipients = $derived(
		(recipientsQuery.data?.pages ?? []).flatMap((page) => page.recipients)
	);

	const statusOptions: { value: MarketingCampaignRecipientFilter | ''; label: string }[] = [
		{ value: '', label: 'All recipients' },
		{ value: 'waiting', label: 'Waiting' },
		{ value: 'delivered', label: 'Delivered' },
		{ value: 'failed', label: 'Failed' },
		{ value: 'excluded', label: 'Excluded' },
		{ value: 'unsubscribed', label: 'Unsubscribed' },
		{ value: 'engaged', label: 'Engaged (opened)' }
	];

	const columns: DataTableColumn[] = [
		{ key: 'customer', label: 'Customer' },
		{ key: 'email', label: 'Email' },
		{ key: 'status', label: 'Status' },
		{ key: 'reason', label: 'Reason' },
		{ key: 'delivered', label: 'Delivered' },
		{ key: 'engagement', label: 'Engagement' },
		{ key: 'attributed', label: 'Attributed to' }
	];

	const dateTimeFormat = new Intl.DateTimeFormat('en-US', {
		dateStyle: 'medium',
		timeStyle: 'short'
	});
	function formatWhen(value: string | null) {
		return value ? dateTimeFormat.format(new Date(value)) : '—';
	}

	function attributedHref(recipient: MarketingCampaignRecipient): string | null {
		if (!recipient.credit) return null;
		if (recipient.credit.request_id) {
			return resolve('/(app)/requests/[id=uuid]', { id: recipient.credit.request_id });
		}
		if (recipient.credit.job_id) {
			return resolve('/(app)/jobs/[id=uuid]', { id: recipient.credit.job_id });
		}
		return null;
	}
</script>

<div class="recipients-panel">
	<div class="recipients-panel__toolbar">
		<SearchInput
			id="campaign-recipients-search"
			bind:value={search}
			placeholder="Search recipients"
		/>
		<Select
			id="campaign-recipients-status"
			bind:value={statusFilter}
			options={statusOptions}
			ariaLabel="Filter by result"
		/>
	</div>

	{#if recipientsQuery.isPending}
		<LoadingSkeleton variant="table" rows={5} label="Loading recipients" />
	{:else if recipientsQuery.isError}
		<ErrorState
			description="Recipients could not be loaded."
			retry={() => recipientsQuery.refetch()}
		/>
	{:else if recipients.length === 0}
		<EmptyState
			icon={usersIcon}
			title={statusFilter || debouncedSearch ? 'No matching recipients' : 'No recipients yet'}
			description={statusFilter || debouncedSearch
				? 'Try a different search term or filter.'
				: 'This campaign has no recorded recipients.'}
		/>
	{:else}
		<DataTable
			{columns}
			items={recipients}
			rowId={(recipient) => recipient.id}
			caption="Recipients"
		>
			{#snippet row(recipient: MarketingCampaignRecipient)}
				<th scope="row">
					<div class="recipients-panel__customer">
						<Avatar id={recipient.client_id} name={recipient.display_name} size="small" />
						<a href={resolve('/(app)/clients/[id=uuid]', { id: recipient.client_id })}>
							{recipient.display_name}
						</a>
					</div>
				</th>
				<td>{recipient.recipient_email ?? '—'}</td>
				<td>
					<StatusBadge status={marketingRecipientStatusTones[recipient.status as never]}>
						{marketingRecipientStatusLabels[recipient.status as never] ?? recipient.status}
					</StatusBadge>
				</td>
				<td>
					{recipient.excluded_reason
						? (marketingExcludedReasonLabels[recipient.excluded_reason] ??
							recipient.excluded_reason)
						: '—'}
				</td>
				<td>{formatWhen(recipient.delivered_at)}</td>
				<td>
					<div class="recipients-panel__engagement">
						{#if recipient.first_opened_at}<span class="tag">Opened</span>{/if}
						{#if recipient.first_clicked_at}<span class="tag">Clicked</span>{/if}
						{#if recipient.unsubscribed_at}<span class="tag tag--warn">Unsubscribed</span>{/if}
						{#if !recipient.first_opened_at && !recipient.first_clicked_at && !recipient.unsubscribed_at}
							—
						{/if}
					</div>
				</td>
				<td>
					{#if recipient.credit}
						{@const href = attributedHref(recipient)}
						<div class="recipients-panel__attributed">
							{#if href}<a {href}>{recipient.credit.request_id ? 'Request' : 'Job'}</a>{/if}
							<span class="tag"
								>{recipient.credit.source === 'tracked' ? 'Direct' : 'Declared'}</span
							>
						</div>
					{:else}
						—
					{/if}
				</td>
			{/snippet}
			{#snippet footer()}
				<ListLoadMore
					hasNextPage={recipientsQuery.hasNextPage}
					isFetchingNextPage={recipientsQuery.isFetchingNextPage}
					onLoadMore={() => recipientsQuery.fetchNextPage()}
				/>
			{/snippet}
		</DataTable>
	{/if}
</div>

<style lang="scss">
	.recipients-panel {
		display: grid;
		gap: var(--space-base);
	}

	.recipients-panel__toolbar {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		flex-wrap: wrap;
	}

	.recipients-panel__customer {
		display: flex;
		align-items: center;
		gap: var(--space-small);

		a {
			color: var(--color-heading);
			font-weight: 700;
			text-decoration: none;

			&:hover {
				text-decoration: underline;
			}
		}
	}

	.recipients-panel__engagement,
	.recipients-panel__attributed {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		flex-wrap: wrap;
	}

	.tag {
		display: inline-flex;
		padding: 2px 8px;
		border-radius: var(--radius-circle);
		background: var(--color-surface--background--subtle);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		white-space: nowrap;

		&--warn {
			background: var(--color-warning--surface);
			color: var(--color-warning--onSurface);
		}
	}
</style>
