<script lang="ts">
	import { createInfiniteQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import FilterBar from '$lib/components/data-display/FilterBar.svelte';
	import FilterField from '$lib/components/data-display/FilterField.svelte';
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
		{ key: 'title', label: 'Title' },
		{ key: 'text', label: 'Text' },
		{ key: 'updated', label: 'Updated' }
	];
</script>

<svelte:head><title>Snippets · Communications · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<div class="snippets-page">
		<PageHeader
			eyebrow="Communications"
			title="Snippets"
			description="Reusable text your team can drop into any conversation reply."
		>
			{#snippet actions()}
				<Button href={resolve('/settings')} variant="secondary" variation="subtle">
					Back to settings
				</Button>
				<Button onclick={() => (dialogState = { mode: 'create' })}>New snippet</Button>
			{/snippet}
		</PageHeader>

		{#if itemsQuery.isPending}
			<LoadingSkeleton variant="table" label="Loading Snippets" rows={5} />
		{:else if itemsQuery.isError}
			<ErrorState
				description="Snippets could not be loaded. Refresh and try again."
				retry={() => itemsQuery.refetch()}
			/>
		{:else}
			<FilterBar onClear={hasFilters ? clearFilters : undefined}>
				<FilterField id="snippets-search" label="Search">
					<SearchInput
						id="snippets-search"
						bind:value={search}
						placeholder="Search title or text"
						ariaLabel="Search Snippets"
					/>
				</FilterField>
				<FilterField id="snippets-folder" label="Folder">
					<Select
						id="snippets-folder"
						value={folder}
						onchange={(value) => (folder = value)}
						options={[{ value: '', label: 'All folders' }, ...folderOptions]}
					/>
				</FilterField>
			</FilterBar>

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
				<DataTable {columns} {items} rowId={(item) => item.id} caption="Snippets">
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
						<DropdownMenu triggerLabel={`Actions for ${item.title}`} items={itemMenuItems(item)} />
					{/snippet}
					{#snippet footer()}
						<ListLoadMore
							hasNextPage={itemsQuery.hasNextPage}
							isFetchingNextPage={itemsQuery.isFetchingNextPage}
							onLoadMore={() => itemsQuery.fetchNextPage()}
						/>
					{/snippet}
				</DataTable>
			{/if}
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
	.snippets-page__title {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
	}

	.snippets-page__text {
		display: -webkit-box;
		overflow: hidden;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		-webkit-box-orient: vertical;
		-webkit-line-clamp: 2;
		line-clamp: 2;
	}
</style>
