<script lang="ts">
	import {
		createInfiniteQuery,
		createMutation,
		createQuery,
		useQueryClient
	} from '@tanstack/svelte-query';
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
	import { page } from '$app/state';
	import uploadIcon from '@tabler/icons/outline/upload.svg?raw';
	import downloadIcon from '@tabler/icons/outline/download.svg?raw';
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
		fetchClient,
		setClientsArchived,
		clientDetailKey,
		clientsListKey,
		type ClientListItem,
		type ClientListPage,
		type ClientOpenWork,
		type ClientReadError,
		type ClientSortKey
	} from '$lib/clients/api';
	import { fetchTags, tagsKey } from '$lib/collaboration/api';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import filterIcon from '@tabler/icons/outline/filter.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import archiveIcon from '@tabler/icons/outline/archive.svg?raw';
	import restoreIcon from '@tabler/icons/outline/archive-off.svg?raw';
	import mergeIcon from '@tabler/icons/outline/arrow-merge.svg?raw';
	import ClientMergeDialog from '$lib/components/clients/ClientMergeDialog.svelte';

	const toast = getToastManager();
	const queryClient = useQueryClient();

	let search = $state('');
	let debouncedSearch = $state('');
	let status = $state<'lead' | 'customer' | 'archived' | ''>('');
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

	// Deleting a client outright is still switched off; archiving is what the office uses instead. The
	// reason is spelled out for screen readers too, because a disabled button never takes focus.
	const deleteReason = 'Not ready yet — archive a client instead of deleting them.';

	$effect(() => {
		const value = search;
		const handle = setTimeout(() => (debouncedSearch = value), 300);
		return () => clearTimeout(handle);
	});

	function setStatus(value: string) {
		status = value as 'lead' | 'customer' | 'archived' | '';
		selectedIds = new Set();
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
	// The server answers whether this member may archive; the page never guesses from a role.
	const canArchive = $derived(clientsQuery.data?.pages[0]?.can_archive === true);
	const viewingArchived = $derived(status === 'archived');
	const canMerge = $derived(clientsQuery.data?.pages[0]?.can_merge === true);
	let mergeOpen = $state(false);
	const tagOptions = $derived([
		{ value: '', label: 'All tags' },
		...(tagsQuery.data ?? []).map((tag) => ({ value: tag.id, label: tag.name }))
	]);
	const hasActiveFilters = $derived(status !== '' || tagId !== '');
	// A 403 never changes on retry, so the page swaps its whole toolbar for one clear answer — search,
	// filters, and New Client are meaningless to someone who cannot see the list.
	const refused = $derived((clientsQuery.error as ClientReadError | null)?.status === 403);

	// Exporting the whole client book is an owner/admin action (the API enforces it too); hide it from other
	// roles rather than let them click into a 403.
	const canExport = $derived(
		page.data.organization?.role === 'owner' || page.data.organization?.role === 'admin'
	);
	const moreClientActions = $derived([
		{
			label: 'Import clients',
			icon: uploadIcon,
			onSelect: () => goto(resolve('/(app)/clients/import'))
		},
		...(canMerge
			? [{ label: 'Merge clients', icon: mergeIcon, onSelect: () => (mergeOpen = true) }]
			: []),
		...(canExport
			? [
					{
						label: 'Export clients',
						icon: downloadIcon,
						// A GET that streams a zip as an attachment; the browser downloads it without leaving the page.
						onSelect: () => {
							window.location.href = '/api/exports/clients';
						}
					}
				]
			: [])
	]);

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
		return resolve('/(app)/clients/[id=uuid]', { id: client.id });
	}
	function clientMenuItems(client: ClientListItem) {
		const archived = client.archived_at !== null;
		return [
			{ label: 'View client', onSelect: () => goto(clientHref(client)) },
			{
				label: 'Edit',
				onSelect: () => goto(resolve('/(app)/clients/[id=uuid]/edit', { id: client.id }))
			},
			...(canArchive
				? [
						archived
							? {
									label: 'Restore',
									icon: restoreIcon,
									onSelect: () => archiveMutation.mutate({ ids: [client.id], archived: false })
								}
							: {
									label: 'Archive',
									icon: archiveIcon,
									onSelect: () => (archiveTarget = { ids: [client.id], name: client.display_name })
								}
					]
				: [])
		];
	}

	// Archiving follows Jobber: the client keeps everything and only leaves the working list, so it is a
	// confirmation rather than a warning, and it is refused outright while live work remains.
	let archiveTarget = $state<{ ids: string[]; name: string | null } | null>(null);

	function blockedSentence(open: ClientOpenWork) {
		const parts = [
			open.requests === 1
				? '1 open request'
				: open.requests > 1
					? `${open.requests} open requests`
					: '',
			open.quotes === 1 ? '1 open quote' : open.quotes > 1 ? `${open.quotes} open quotes` : '',
			open.jobs === 1 ? '1 job still open' : open.jobs > 1 ? `${open.jobs} jobs still open` : '',
			open.invoices === 1
				? '1 unpaid invoice'
				: open.invoices > 1
					? `${open.invoices} unpaid invoices`
					: ''
		].filter(Boolean);
		return parts.join(', ');
	}

	const archiveMutation = createMutation<
		Awaited<ReturnType<typeof setClientsArchived>>,
		Error,
		{ ids: string[]; archived: boolean }
	>(() => ({
		mutationFn: ({ ids, archived }) => setClientsArchived(ids, archived),
		onSuccess: (result, variables) => {
			archiveTarget = null;
			selectedIds = new Set();
			void queryClient.invalidateQueries({ queryKey: ['clients'] });
			// Each archived or restored client gains a line in its history.
			void queryClient.invalidateQueries({ queryKey: ['collaboration', 'activity', 'client'] });

			const blocked = result.results.find((outcome) => outcome.open_work !== null);
			if (result.changed === 0 && blocked?.open_work) {
				toast.error(
					'This client still has live work',
					`Finish or archive it first — ${blockedSentence(blocked.open_work)}.`
				);
				return;
			}
			if (!variables.archived) {
				toast.success(
					result.changed === 1 ? 'Client restored.' : `${result.changed} clients restored.`
				);
				return;
			}
			const archivedLine =
				result.changed === 1 ? 'Client archived.' : `${result.changed} clients archived.`;
			if (result.skipped > 0) {
				toast.warning(archivedLine, `${result.skipped} kept, because they still have live work.`);
				return;
			}
			toast.success(archivedLine, 'Their history stays, and new work brings them back.');
		},
		onError: (error) => toast.error(error.message)
	}));

	function prefetchClient(item: { id: string }) {
		void queryClient.prefetchQuery({
			queryKey: clientDetailKey(item.id),
			queryFn: () => fetchClient(item.id),
			staleTime: 15_000
		});
	}
</script>

<svelte:head><title>Clients · Contractor CRM</title></svelte:head>

{#if mergeOpen}
	<ClientMergeDialog open onClose={() => (mergeOpen = false)} />
{/if}

<PageContainer variant="fill">
	<PageHeader title="Clients" description="Every lead and customer relationship in one place.">
		{#snippet actions()}
			{#if !refused}
				<div class="clients-header-actions">
					<DropdownMenu triggerLabel="More client actions" items={moreClientActions} />
					<Button variant="primary" href={resolve('/clients/new')}>New Client</Button>
				</div>
			{/if}
		{/snippet}
	</PageHeader>

	{#if refused}
		<EmptyState
			icon={lockIcon}
			title="You do not have access to clients"
			description="Clients on your assigned visits open from the Schedule and your Jobs. Ask an owner or admin if you need the full client list."
		/>
	{:else}
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
							{ value: 'customer', label: 'Customer' },
							// Archived clients live in this same list behind their own filter, the way Jobber
							// keeps them — they are never a separate screen.
							{ value: 'archived', label: 'Archived' }
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
				{#if canArchive}
					{#if viewingArchived}
						<Button
							variant="secondary"
							size="small"
							loading={archiveMutation.isPending}
							onclick={() => archiveMutation.mutate({ ids: [...selectedIds], archived: false })}
							>Restore</Button
						>
					{:else}
						<Button
							variant="secondary"
							size="small"
							loading={archiveMutation.isPending}
							onclick={() => (archiveTarget = { ids: [...selectedIds], name: null })}
							>Archive</Button
						>
					{/if}
				{/if}
				<span class="clients-bulk-bar__action" title={deleteReason}>
					<Button variant="secondary" variation="destructive" size="small" disabled>Delete</Button>
					<span class="clients-bulk-bar__reason">{deleteReason}</span>
				</span>
			</div>
		{/if}

		{#if clientsQuery.isPending}
			<LoadingSkeleton variant="table" label="Loading clients" rows={5} />
		{:else if clientsQuery.isError}
			<ErrorState
				description="Clients could not be loaded. Try again."
				retry={() => clientsQuery.refetch()}
			/>
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
				onRowHover={prefetchClient}
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
					<td>
						{#if client.archived_at}
							<Badge>Archived</Badge>
						{:else}
							<Badge status={client.lifecycle_status === 'customer' ? 'success' : 'informative'}
								>{statusLabel(client.lifecycle_status)}</Badge
							>
						{/if}
					</td>
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
	{/if}
</PageContainer>

<ConfirmDialog
	open={archiveTarget !== null}
	title={archiveTarget && archiveTarget.ids.length > 1 ? 'Archive these clients' : 'Archive client'}
	icon={archiveIcon}
	confirmLabel="Archive"
	loading={archiveMutation.isPending}
	confirmDisabled={archiveMutation.isPending}
	onConfirm={() => {
		if (archiveTarget) archiveMutation.mutate({ ids: archiveTarget.ids, archived: true });
	}}
	onClose={() => {
		if (!archiveMutation.isPending) archiveTarget = null;
	}}
>
	<p>
		{#if archiveTarget?.name}
			<strong>{archiveTarget.name}</strong> leaves your client list.
		{:else}
			{archiveTarget?.ids.length} clients leave your client list.
		{/if}
		Everything stays — past quotes, jobs, invoices and messages — and you can find them again under the
		Archived status filter. Starting new work for them brings them back automatically.
	</p>
</ConfirmDialog>

<style lang="scss">
	.clients-header-actions {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

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
