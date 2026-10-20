<script lang="ts">
	import { createInfiniteQuery, useQueryClient } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import SettingsPageHeader from '$lib/components/settings/SettingsPageHeader.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import FilterChip from '$lib/components/ui/FilterChip.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import RecordListCard from '$lib/components/data-display/RecordListCard.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import SnippetDialog from '$lib/components/communications/SnippetDialog.svelte';
	import { relativeTime, exactTime } from '$lib/collaboration/format';
	import {
		communicationSnippetsKey,
		deleteCommunicationSnippet,
		fetchCommunicationSnippets,
		SnippetWriteError,
		type CommunicationSnippet,
		type CommunicationSnippetPage
	} from '$lib/communications/snippets';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import quoteIcon from '@tabler/icons/outline/quote.svg?raw';
	import folderIcon from '@tabler/icons/outline/folder.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	// Settings → Communications → Snippets: reusable text the composer picker also reads. `conversations.send`
	// gates this route the same way it gates the picker -- see the migration's own comment for why one
	// permission covers both.
	const queryClient = useQueryClient();
	const toast = getToastManager();

	let search = $state('');
	let debouncedSearch = $state('');
	let folder = $state('');
	let dialogState = $state<{ mode: 'create' | 'update'; snippet?: CommunicationSnippet } | null>(
		null
	);
	let deleteTarget = $state<CommunicationSnippet | null>(null);
	let deleting = $state(false);

	$effect(() => {
		const value = search;
		const handle = setTimeout(() => (debouncedSearch = value), 300);
		return () => clearTimeout(handle);
	});

	const filters = $derived({ search: debouncedSearch, folder: folder || undefined });

	const itemsQuery = createInfiniteQuery(() => ({
		queryKey: communicationSnippetsKey(filters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchCommunicationSnippets(filters, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (page: CommunicationSnippetPage) => page.next_cursor ?? undefined,
		staleTime: 30_000
	}));

	const items = $derived(itemsQuery.data?.pages.flatMap((page) => page.items) ?? []);
	const hasFilters = $derived(Boolean(search.trim() || folder));

	// Folder options come from what is already loaded rather than a second endpoint -- a business's
	// snippet library is a bounded handful of rows (see the migration), so the first page or two already
	// carries every folder in practice.
	const folderOptions = $derived(
		Array.from(new Set(items.map((item) => item.folder).filter((name): name is string => !!name)))
			.sort((a, b) => a.localeCompare(b))
			.map((name) => ({ value: name, label: name }))
	);

	function clearFilters() {
		search = '';
		debouncedSearch = '';
		folder = '';
	}

	async function invalidate() {
		await queryClient.invalidateQueries({ queryKey: ['communications', 'snippets'] });
	}

	function itemMenuItems(item: CommunicationSnippet) {
		return [
			{
				label: 'Edit',
				icon: pencilIcon,
				onSelect: () => (dialogState = { mode: 'update', snippet: item })
			},
			{
				label: 'Delete',
				icon: trashIcon,
				destructive: true,
				onSelect: () => (deleteTarget = item)
			}
		];
	}

	function snippetSaved() {
		const wasUpdate = dialogState?.mode === 'update';
		dialogState = null;
		void invalidate();
		toast.success(wasUpdate ? 'Snippet saved.' : 'Snippet added.');
	}

	async function confirmDelete() {
		if (!deleteTarget) return;
		deleting = true;
		try {
			await deleteCommunicationSnippet(deleteTarget.id);
			deleteTarget = null;
			await invalidate();
			toast.success('Snippet deleted.');
		} catch (cause) {
			toast.error(
				cause instanceof SnippetWriteError ? cause.message : 'That snippet could not be deleted.'
			);
		} finally {
			deleting = false;
		}
	}

	const columns: DataTableColumn[] = [
		{ key: 'title', label: 'Title', width: '300px' },
		{ key: 'text', label: 'Text' },
		{ key: 'updated', label: 'Updated', width: '170px' }
	];
</script>

<svelte:head><title>Snippets · Communications · Contractor CRM</title></svelte:head>

<PageContainer variant="open">
	<div class="snippets-page">
		<SettingsPageHeader
			title="Snippets"
			description="Reusable text your team can drop into any conversation reply."
			icon={quoteIcon}
			tone="task"
			presentation="communication"
		>
			{#snippet actions()}
				<Button onclick={() => (dialogState = { mode: 'create' })}>New snippet</Button>
			{/snippet}
		</SettingsPageHeader>

		{#if itemsQuery.isPending}
			<RecordListCard title="Snippets" padBody>
				<LoadingSkeleton variant="table" label="Loading Snippets" rows={5} />
			</RecordListCard>
		{:else if itemsQuery.isError}
			<RecordListCard title="Snippets" padBody>
				<ErrorState
					description="Snippets could not be loaded. Refresh and try again."
					retry={() => itemsQuery.refetch()}
				/>
			</RecordListCard>
		{:else}
			<RecordListCard title="Snippets" padBody={items.length === 0}>
				{#snippet toolbar()}
					<div class="snippets-page__search">
						<SearchInput
							id="snippets-search"
							bind:value={search}
							placeholder="Search title or text"
							ariaLabel="Search Snippets"
							size="compact"
						/>
					</div>
					<FilterChip
						id="snippets-folder"
						variant="toolbar"
						icon={folderIcon}
						label="Folder"
						value={folder}
						options={[{ value: '', label: 'All folders' }, ...folderOptions]}
						restValue=""
						onchange={(value) => (folder = value)}
					/>
					{#if hasFilters}
						<Button variant="tertiary" size="small" onclick={clearFilters}>Clear filters</Button>
					{/if}
				{/snippet}

				{#if items.length === 0}
					<EmptyState
						icon={fileTextIcon}
						title={hasFilters ? 'Nothing matches that' : 'No snippets yet'}
						description={hasFilters
							? 'Try a different search term or clear your filters.'
							: 'Save the replies your team sends often, and they will be one click away in the composer.'}
					>
						{#snippet action()}
							<Button variant="secondary" onclick={() => (dialogState = { mode: 'create' })}>
								New snippet
							</Button>
						{/snippet}
					</EmptyState>
				{:else}
					<DataTable variant="card" {columns} {items} rowId={(item) => item.id} caption="Snippets">
						{#snippet row(item: CommunicationSnippet)}
							<th scope="row">
								<div class="snippets-page__title">
									<strong>{item.title}</strong>
									{#if item.folder}<Badge size="small">{item.folder}</Badge>{/if}
								</div>
							</th>
							<td>
								<span class="snippets-page__text">{item.body}</span>
							</td>
							<td>
								<span title={exactTime(item.updated_at)}>{relativeTime(item.updated_at)}</span>
							</td>
						{/snippet}
						{#snippet rowActions(item: CommunicationSnippet)}
							<DropdownMenu
								triggerLabel={`Actions for ${item.title}`}
								items={itemMenuItems(item)}
							/>
						{/snippet}
						{#snippet footer()}
							<ListLoadMore
 count={items.length} recordName="items" recordColor="inactive"
								variant="card"
								hasNextPage={itemsQuery.hasNextPage}
								isFetchingNextPage={itemsQuery.isFetchingNextPage}
								onLoadMore={() => itemsQuery.fetchNextPage()}
							/>
						{/snippet}
					</DataTable>
				{/if}
			</RecordListCard>
		{/if}
	</div>
</PageContainer>

{#if dialogState}
	<SnippetDialog
		open={true}
		mode={dialogState.mode}
		snippet={dialogState.snippet}
		existingFolders={folderOptions.map((option) => option.value)}
		onSaved={snippetSaved}
		onClose={() => (dialogState = null)}
	/>
{/if}

<ConfirmDialog
	open={deleteTarget !== null}
	title="Delete this snippet?"
	tone="critical"
	destructive
	confirmLabel="Delete snippet"
	loading={deleting}
	onConfirm={() => void confirmDelete()}
	onClose={() => (deleteTarget = null)}
>
	{#if deleteTarget}
		<p>This can't be undone. "{deleteTarget.title}" will no longer be available in the composer.</p>
	{/if}
</ConfirmDialog>

<style lang="scss">
	.snippets-page {
		display: flex;
		flex-direction: column;
		gap: 20px;
	}
	.snippets-page__search {
		width: 300px;
		max-width: 100%;
	}

	.snippets-page__title {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: var(--space-smaller);

		strong {
			color: var(--color-heading);
			font-weight: 600;
		}
	}

	.snippets-page__text {
		display: -webkit-box;
		overflow: hidden;
		color: var(--color-text);
		font-size: 13px;
		line-height: 1.55;
		-webkit-box-orient: vertical;
		-webkit-line-clamp: 2;
		line-clamp: 2;
	}
</style>
