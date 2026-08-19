<script lang="ts">
	import { createInfiniteQuery, createQuery } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import FilterBar from '$lib/components/data-display/FilterBar.svelte';
	import FilterField from '$lib/components/data-display/FilterField.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import DataTable, {
		type DataTableColumn,
		type DataTableSort
	} from '$lib/components/data-display/DataTable.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
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
		type RequestListPage,
		type RequestSortKey
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
	let sortKey = $state<RequestSortKey>('requested');
	let sortDir = $state<'asc' | 'desc'>('desc');

	// Click a header to sort by it ascending; click it again for descending. Clicking a different
	// sortable header switches to that column, starting ascending again — one sort column at a time.
	function handleSortChange(key: string) {
		if (key === sortKey) {
			sortDir = sortDir === 'asc' ? 'desc' : 'asc';
		} else {
			sortKey = key as RequestSortKey;
			sortDir = 'asc';
		}
	}

	// Nothing behind these yet. Each says why rather than sitting there dead, the way the Clients page does.
	const bulkReason = 'Not ready yet — this arrives with the request actions.';
	const moreActionsReason = 'Booking form settings arrive with the public request form.';

	$effect(() => {
		const value = search;
		const handle = setTimeout(() => (debouncedSearch = value), 300);
		return () => clearTimeout(handle);
	});

	const filters = $derived({
		search: debouncedSearch,
		statuses: status ? [status] : [],
		sort: sortKey,
		dir: sortDir
	});
	const sort = $derived<DataTableSort>({ key: sortKey, direction: sortDir });

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

	function requestHref(request: RequestListItem) {
		return resolve('/(app)/requests/[id]', { id: request.id });
	}

	const columns: DataTableColumn[] = [
		{ key: 'client', label: 'Client' },
		{ key: 'title', label: 'Title', sortable: true },
		{ key: 'property', label: 'Property' },
		{ key: 'contact', label: 'Contact' },
		{ key: 'requested', label: 'Requested', sortable: true },
		{ key: 'status', label: 'Status' }
	];
</script>

<svelte:head><title>Requests · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<PageHeader title="Requests" description="Every job someone has asked you to look at.">
		{#snippet actions()}
			<Button variant="primary" href={resolve('/(app)/requests/new')}>New Request</Button>
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
		<FilterBar onClear={hasActiveFilters ? () => (status = '') : undefined}>
			<FilterField id="requests-status-filter" label="Status">
				<Select
					id="requests-status-filter"
					value={status}
					onchange={(value) => (status = value as StoredRequestStatus | '')}
					options={statusOptions}
				/>
			</FilterField>
		</FilterBar>
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
			onRowActivate={(request) => goto(requestHref(request))}
			{sort}
			onSortChange={handleSortChange}
		>
			{#snippet row(request: RequestListItem)}
				<th scope="row">
					<div class="requests-table__client">
						<Avatar id={request.client?.id ?? request.id} name={clientName(request)} size="small" />
						<span>{clientName(request)}</span>
					</div>
				</th>
				<td>
					<a class="requests-table__title" href={requestHref(request)}>{request.title}</a>
				</td>
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
						{ label: 'View request', onSelect: () => void goto(requestHref(request)) },
						{ label: 'Archive', onSelect: () => {}, disabled: true }
					]}
					triggerLabel={`Actions for ${request.title}`}
				/>
			{/snippet}
			{#snippet footer()}
				<ListLoadMore
					hasNextPage={requestsQuery.hasNextPage}
					isFetchingNextPage={requestsQuery.isFetchingNextPage}
					onLoadMore={() => requestsQuery.fetchNextPage()}
				/>
			{/snippet}
		</DataTable>
	{/if}
</PageContainer>

<style lang="scss">
	.requests-table__client {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

	.requests-table__title {
		color: var(--color-heading);
		font-weight: 700;
		text-decoration: none;

		&:hover {
			text-decoration: underline;
		}
	}

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
