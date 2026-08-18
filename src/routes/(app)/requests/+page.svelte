<script lang="ts">
	import { createInfiniteQuery, createQuery } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import StatusOverviewCard from '$lib/components/work/StatusOverviewCard.svelte';
	import type { StatusOverviewRow } from '$lib/components/work/types';
	import {
		fetchRequestCounts,
		fetchRequests,
		requestCountsKey,
		requestsListKey,
		type RequestListItem,
		type RequestListPage
	} from '$lib/requests/api';
	import {
		REQUEST_STATUS_LABELS,
		REQUEST_STATUS_TONES,
		STORED_REQUEST_STATUSES,
		type StoredRequestStatus
	} from '$lib/requests/statuses';
	import clipboardIcon from '@tabler/icons/outline/clipboard-list.svg?raw';
	import filterIcon from '@tabler/icons/outline/filter.svg?raw';
	import chartIcon from '@tabler/icons/outline/chart-bar.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar-stats.svg?raw';
	import trendingIcon from '@tabler/icons/outline/trending-up.svg?raw';

	let search = $state('');
	let debouncedSearch = $state('');
	let status = $state<StoredRequestStatus | ''>('');
	let filtersOpen = $state(false);
	let selectedIds = $state<Set<string>>(new Set());

	// Nothing behind these yet. Each says why rather than sitting there dead, the way the Clients page does.
	const bulkReason = 'Not ready yet — this arrives with the request actions.';
	const newRequestReason = 'The New Request page is next up.';
	const moreActionsReason = 'Booking form settings arrive with the public request form.';

	$effect(() => {
		const value = search;
		const handle = setTimeout(() => (debouncedSearch = value), 300);
		return () => clearTimeout(handle);
	});

	const filters = $derived({
		search: debouncedSearch,
		statuses: status ? [status] : []
	});

	// Keyset pagination, so there is no page to jump to — each page hands back the cursor for the next one
	// and Load more asks for it. That is what keeps the query fast however many requests an office has.
	const requestsQuery = createInfiniteQuery(() => ({
		queryKey: requestsListKey(filters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchRequests(filters, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage: RequestListPage) => lastPage.next_cursor ?? undefined
	}));

	const countsQuery = createQuery(() => ({
		queryKey: requestCountsKey,
		queryFn: fetchRequestCounts
	}));

	const requests = $derived(requestsQuery.data?.pages.flatMap((page) => page.requests) ?? []);
	const hasActiveFilters = $derived(status !== '');

	// The four the office acts on. Counted, never clickable — filtering lives on the Status chip below,
	// the same split Jobber uses.
	const overviewRows = $derived<StatusOverviewRow[]>(
		(['new', 'unscheduled', 'overdue', 'assessment_completed'] as const).map((key) => ({
			label: REQUEST_STATUS_LABELS[key],
			count: countsQuery.data?.[key] ?? 0,
			tone: REQUEST_STATUS_TONES[key]
		}))
	);

	const statusOptions = [
		{ value: '', label: 'All statuses' },
		...STORED_REQUEST_STATUSES.map((value) => ({ value, label: REQUEST_STATUS_LABELS[value] }))
	];

	const dateFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	});

	function propertyAddress(property: RequestListItem['property']) {
		if (!property) return 'No property';
		return [property.address_line1, property.city, property.state_region]
			.filter(Boolean)
			.join(', ');
	}
	function clientName(request: RequestListItem) {
		return request.client?.display_name ?? 'Client removed';
	}

	const columns: DataTableColumn[] = [
		{ key: 'client', label: 'Client' },
		{ key: 'title', label: 'Title' },
		{ key: 'property', label: 'Property' },
		{ key: 'contact', label: 'Contact' },
		{ key: 'requested', label: 'Requested' },
		{ key: 'status', label: 'Status' }
	];
</script>

<svelte:head><title>Requests · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<PageHeader title="Requests" description="Every job someone has asked you to look at.">
		{#snippet actions()}
			<span class="requests-header__action" title={newRequestReason}>
				<Button variant="primary" disabled>New Request</Button>
				<span class="requests-header__reason">{newRequestReason}</span>
			</span>
			<span class="requests-header__action" title={moreActionsReason}>
				<Button variant="secondary" disabled>More Actions</Button>
				<span class="requests-header__reason">{moreActionsReason}</span>
			</span>
		{/snippet}
	</PageHeader>

	<div class="requests-stats">
		<StatusOverviewCard rows={overviewRows} loading={countsQuery.isPending} />
		<KpiCard
			label="New requests"
			value="—"
			note="Once there are 30 days of requests to compare"
			icon={trendingIcon}
			variant="compact"
		/>
		<KpiCard
			label="Conversion rate"
			value="—"
			note="Once requests turn into quotes and jobs"
			icon={chartIcon}
			variant="compact"
		/>
		<KpiCard
			label="Assessments booked"
			value="—"
			note="Once assessments are being scheduled"
			icon={calendarIcon}
			variant="compact"
		/>
	</div>

	<div class="requests-toolbar">
		<div class="requests-toolbar__search">
			<SearchInput id="requests-search" bind:value={search} placeholder="Search requests" />
		</div>
		<!-- eslint-disable svelte/no-at-html-tags -->
		<button
			type="button"
			class="requests-toolbar__filters-toggle"
			class:requests-toolbar__filters-toggle--active={hasActiveFilters}
			aria-pressed={filtersOpen}
			onclick={() => (filtersOpen = !filtersOpen)}
		>
			<span aria-hidden="true">{@html filterIcon}</span>
			Filters{hasActiveFilters ? ' •' : ''}
		</button>
		<!-- eslint-enable svelte/no-at-html-tags -->
	</div>

	{#if filtersOpen}
		<div class="requests-filters">
			<div class="requests-filters__field">
				<label for="requests-status-filter">Status</label>
				<Select
					id="requests-status-filter"
					value={status}
					onchange={(value) => (status = value as StoredRequestStatus | '')}
					options={statusOptions}
				/>
			</div>
			{#if hasActiveFilters}
				<Button variant="tertiary" size="small" onclick={() => (status = '')}>Clear filters</Button>
			{/if}
		</div>
	{/if}

	{#if selectedIds.size > 0}
		<div class="requests-bulk-bar">
			<span>{selectedIds.size} selected</span>
			<span class="requests-bulk-bar__action" title={bulkReason}>
				<Button variant="secondary" size="small" disabled>Archive</Button>
				<span class="requests-bulk-bar__reason">{bulkReason}</span>
			</span>
		</div>
	{/if}

	{#if requestsQuery.isPending}
		<LoadingSkeleton variant="table" label="Loading requests" rows={5} />
	{:else if requestsQuery.isError}
		<ErrorState description="Requests could not be loaded. Refresh and try again." />
	{:else if requests.length === 0}
		<EmptyState
			icon={clipboardIcon}
			title={hasActiveFilters || debouncedSearch ? 'No matching requests' : 'No requests yet'}
			description={hasActiveFilters || debouncedSearch
				? 'Try a different search term or clear your filters.'
				: 'Work people ask you to look at will show up here.'}
		/>
	{:else}
		<DataTable
			{columns}
			items={requests}
			rowId={(request) => request.id}
			caption="Requests"
			selectable
			bind:selectedIds
			rowLabel={(request) => `Select ${request.title}`}
		>
			{#snippet row(request: RequestListItem)}
				<th scope="row">{clientName(request)}</th>
				<td>{request.title}</td>
				<td>{propertyAddress(request.property)}</td>
				<td>{request.email ?? request.phone ?? '—'}</td>
				<td>{dateFormat.format(new Date(request.requested_at))}</td>
				<td>
					<StatusBadge status={REQUEST_STATUS_TONES[request.status]}>
						{REQUEST_STATUS_LABELS[request.status]}
					</StatusBadge>
				</td>
			{/snippet}
			{#snippet rowActions(request: RequestListItem)}
				<DropdownMenu
					items={[
						{ label: 'View request', onSelect: () => {}, disabled: true },
						{ label: 'Archive', onSelect: () => {}, disabled: true }
					]}
					triggerLabel={`Actions for ${request.title}`}
				/>
			{/snippet}
			{#snippet footer()}
				<div class="requests-more">
					{#if requestsQuery.hasNextPage}
						<Button
							variant="secondary"
							onclick={() => requestsQuery.fetchNextPage()}
							disabled={requestsQuery.isFetchingNextPage}
						>
							{requestsQuery.isFetchingNextPage ? 'Loading…' : 'Load more'}
						</Button>
					{:else}
						<span class="requests-more__end">That is all of them.</span>
					{/if}
				</div>
			{/snippet}
		</DataTable>
	{/if}
</PageContainer>

<style lang="scss">
	.requests-header__action,
	.requests-bulk-bar__action {
		position: relative;
		display: inline-flex;
	}

	.requests-header__reason,
	.requests-bulk-bar__reason {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
	}

	.requests-stats {
		display: grid;
		gap: var(--space-base);
		grid-template-columns: repeat(4, minmax(0, 1fr));
		margin-top: var(--space-large);
	}

	.requests-toolbar {
		display: flex;
		gap: var(--space-small);
		margin: var(--space-large) 0;

		&__search {
			flex: 1;
			min-width: 0;
		}
		&__filters-toggle {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			gap: var(--space-smaller);
			padding: 0 var(--space-base);
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-heading);
			background: var(--color-surface);
			font-weight: 600;
			cursor: pointer;

			:global(svg) {
				width: 18px;
				height: 18px;
			}
			&:hover {
				background: var(--color-surface--hover);
			}
			&--active {
				border-color: var(--color-interactive);
				color: var(--color-interactive);
			}
		}
	}

	.requests-filters {
		display: flex;
		align-items: flex-end;
		gap: var(--space-base);
		margin-bottom: var(--space-base);

		&__field {
			display: grid;
			gap: var(--space-smaller);

			label {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				font-weight: 600;
			}
		}
	}

	.requests-bulk-bar {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		margin-bottom: var(--space-base);
		padding: var(--space-small) var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		font-weight: 600;
	}

	.requests-more {
		display: flex;
		justify-content: center;
		padding: var(--space-base);

		&__end {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	@media (max-width: 1023px) {
		.requests-stats {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	@media (max-width: 639px) {
		.requests-stats {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
