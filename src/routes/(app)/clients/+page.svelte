<script lang="ts">
	import { createInfiniteQuery, createQuery } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import DataTable, {
		type DataTableColumn,
		type DataTableSort
	} from '$lib/components/data-display/DataTable.svelte';
	import FilterBar from '$lib/components/data-display/FilterBar.svelte';
	import FilterField from '$lib/components/data-display/FilterField.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		fetchClients,
		clientsListKey,
		type ClientListItem,
		type ClientListPage,
		type ClientSortKey
	} from '$lib/clients/api';
	import { fetchTags, tagsKey } from '$lib/collaboration/api';
	import filterIcon from '@tabler/icons/outline/filter.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';

	let search = $state('');
	let debouncedSearch = $state('');
	let status = $state<'lead' | 'customer' | ''>('');
	let tagId = $state('');
	let filtersOpen = $state(false);
	let sortKey = $state<ClientSortKey>('updated_at');
	let sortDir = $state<'asc' | 'desc'>('desc');

	// Click a header to sort by it ascending; click it again for descending. Clicking a different
	// sortable header switches to that column, starting ascending again — one sort column at a time.
	function handleSortChange(key: string) {
		if (key === sortKey) {
			sortDir = sortDir === 'asc' ? 'desc' : 'asc';
		} else {
			sortKey = key as ClientSortKey;
			sortDir = 'asc';
		}
	}

	// Both bulk actions are switched off until clients carry real work to archive or delete alongside.
	// The reason is spelled out for screen readers too, because a disabled button never takes focus.
	const bulkReason = 'Not ready yet — this arrives once clients carry work.';

	$effect(() => {
		const value = search;
		const handle = setTimeout(() => (debouncedSearch = value), 300);
		return () => clearTimeout(handle);
	});

	function setStatus(value: string) {
		status = value as 'lead' | 'customer' | '';
	}
	function setTag(value: string) {
		tagId = value;
	}
	function clearFilters() {
		status = '';
		tagId = '';
	}

	const filters = $derived({
		search: debouncedSearch,
		status,
		tagId,
		sort: sortKey,
		dir: sortDir
	});
	const sort = $derived<DataTableSort>({ key: sortKey, direction: sortDir });

	// Keyset pagination, so there is no page to jump to — each page hands back the cursor for the next one
	// and Load more asks for it. That is what keeps the query fast however many clients an office has.
	const clientsQuery = createInfiniteQuery(() => ({
		queryKey: clientsListKey(filters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) => fetchClients(filters, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage: ClientListPage) => lastPage.next_cursor ?? undefined
	}));
	const tagsQuery = createQuery(() => ({ queryKey: tagsKey, queryFn: fetchTags }));

	const clients = $derived(clientsQuery.data?.pages.flatMap((page) => page.clients) ?? []);
	const tagOptions = $derived([
		{ value: '', label: 'All tags' },
		...(tagsQuery.data ?? []).map((tag) => ({ value: tag.id, label: tag.name }))
	]);
	const hasActiveFilters = $derived(status !== '' || tagId !== '');

	let selectedIds = $state<Set<string>>(new Set());

	function formatAddress(property: ClientListItem['primary_property']) {
		if (!property) return 'No property yet';
		return [property.address_line1, property.city, property.state_region]
			.filter(Boolean)
			.join(', ');
	}
	function statusLabel(lifecycleStatus: string) {
		return lifecycleStatus === 'customer' ? 'Customer' : 'Lead';
	}

	const columns: DataTableColumn[] = [
		{ key: 'name', label: 'Name', sortable: true },
		{ key: 'address', label: 'Address' },
		{ key: 'contact', label: 'Email & Phone' },
		{ key: 'tags', label: 'Tags' },
		{ key: 'status', label: 'Status', sortable: true }
	];
	function clientHref(client: ClientListItem) {
		return resolve('/(app)/clients/[id]', { id: client.id });
	}
	function clientMenuItems(client: ClientListItem) {
		return [
			{ label: 'View client', onSelect: () => goto(clientHref(client)) },
			{
				label: 'Edit',
				onSelect: () => goto(resolve('/(app)/clients/[id]/edit', { id: client.id }))
			},
			{ label: 'Archive', onSelect: () => {}, disabled: true }
		];
	}
</script>

<svelte:head><title>Clients · Contractor CRM</title></svelte:head>

<div class="page-scroller">
	<PageContainer variant="fill">
		<PageHeader title="Clients" description="Every lead and customer relationship in one place.">
			{#snippet actions()}
				<Button variant="primary" href={resolve('/clients/new')}>New Client</Button>
			{/snippet}
		</PageHeader>

		<div class="clients-toolbar">
			<div class="clients-toolbar__search">
				<SearchInput id="clients-search" bind:value={search} placeholder="Search clients" />
			</div>
			<!-- eslint-disable svelte/no-at-html-tags -->
			<button
				type="button"
				class="clients-toolbar__filters-toggle"
				class:clients-toolbar__filters-toggle--active={hasActiveFilters}
				aria-pressed={filtersOpen}
				onclick={() => (filtersOpen = !filtersOpen)}
			>
				<span aria-hidden="true">{@html filterIcon}</span>
				Filters{hasActiveFilters ? ' •' : ''}
			</button>
			<!-- eslint-enable svelte/no-at-html-tags -->
		</div>

		{#if filtersOpen}
			<FilterBar onClear={hasActiveFilters ? clearFilters : undefined}>
				<FilterField id="clients-status-filter" label="Status">
					<Select
						id="clients-status-filter"
						value={status}
						onchange={setStatus}
						options={[
							{ value: '', label: 'All statuses' },
							{ value: 'lead', label: 'Lead' },
							{ value: 'customer', label: 'Customer' }
						]}
					/>
				</FilterField>
				<FilterField id="clients-tag-filter" label="Tag">
					<Select id="clients-tag-filter" value={tagId} onchange={setTag} options={tagOptions} />
				</FilterField>
			</FilterBar>
		{/if}

		{#if selectedIds.size > 0}
			<div class="clients-bulk-bar">
				<span>{selectedIds.size} selected</span>
				<span class="clients-bulk-bar__action" title={bulkReason}>
					<Button variant="secondary" size="small" disabled>Archive</Button>
					<span class="clients-bulk-bar__reason">{bulkReason}</span>
				</span>
				<span class="clients-bulk-bar__action" title={bulkReason}>
					<Button variant="secondary" variation="destructive" size="small" disabled>Delete</Button>
					<span class="clients-bulk-bar__reason">{bulkReason}</span>
				</span>
			</div>
		{/if}

		{#if clientsQuery.isPending}
			<LoadingSkeleton variant="table" label="Loading clients" rows={5} />
		{:else if clientsQuery.isError}
			<ErrorState description="Clients could not be loaded. Refresh and try again." />
		{:else if clients.length === 0}
			<EmptyState
				icon={usersIcon}
				title={hasActiveFilters || debouncedSearch ? 'No matching clients' : 'No clients yet'}
				description={hasActiveFilters || debouncedSearch
					? 'Try a different search term or clear your filters.'
					: 'Clients you add will show up here.'}
			/>
		{:else}
			<DataTable
				{columns}
				items={clients}
				rowId={(client) => client.id}
				caption="Clients"
				selectable
				bind:selectedIds
				rowLabel={(client) => `Select ${client.display_name}`}
				onRowActivate={(client) => goto(clientHref(client))}
				{sort}
				onSortChange={handleSortChange}
			>
				{#snippet row(client: ClientListItem)}
					<th scope="row">
						<div class="clients-table__name">
							<Avatar id={client.id} name={client.display_name} size="small" />
							<a class="clients-table__name-text" href={clientHref(client)}>{client.display_name}</a
							>
						</div>
					</th>
					<td
						>{formatAddress(client.primary_property)}{#if client.additional_property_count > 0}
							<span class="clients-table__more-properties"
								>+{client.additional_property_count} more</span
							>{/if}</td
					>
					<td>{client.email ?? client.phone ?? '—'}</td>
					<td>
						{#if client.tags.length > 0}
							<div class="clients-table__tags">
								{#each client.tags as tag (tag.id)}<Badge>{tag.name}</Badge>{/each}
							</div>
						{:else}
							—
						{/if}
					</td>
					<td
						><Badge status={client.lifecycle_status === 'customer' ? 'success' : 'informative'}
							>{statusLabel(client.lifecycle_status)}</Badge
						></td
					>
				{/snippet}
				{#snippet rowActions(client: ClientListItem)}
					<DropdownMenu
						items={clientMenuItems(client)}
						triggerLabel={`Actions for ${client.display_name}`}
					/>
				{/snippet}
				{#snippet footer()}
					<ListLoadMore
						hasNextPage={clientsQuery.hasNextPage}
						isFetchingNextPage={clientsQuery.isFetchingNextPage}
						onLoadMore={() => clientsQuery.fetchNextPage()}
					/>
				{/snippet}
			</DataTable>
		{/if}
	</PageContainer>
</div>

<style lang="scss">
	.clients-toolbar {
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

	.clients-bulk-bar__action {
		display: inline-flex;
		align-items: center;
	}

	// Read aloud beside the switched-off button; sighted users get the same words as a hover title.
	.clients-bulk-bar__reason {
		position: absolute;
		width: 1px;
		height: 1px;
		margin: -1px;
		padding: 0;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
		border: 0;
	}

	.clients-bulk-bar {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		margin-bottom: var(--space-base);
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-surface--active);
		font-weight: 600;
	}

	.clients-table__name {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}
	.clients-table__name-text {
		color: var(--color-heading);
		font-weight: 700;
		text-decoration: none;

		&:hover {
			text-decoration: underline;
		}
	}
	.clients-table__more-properties {
		display: block;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.clients-table__tags {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-smaller);
	}

	@media (max-width: 767px) {
		.clients-toolbar {
			flex-wrap: wrap;
		}
	}
</style>
