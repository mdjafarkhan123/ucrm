<script lang="ts">
	import { createInfiniteQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
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
		<header class="snippets-page__header">
			<span class="snippets-page__header-icon" aria-hidden="true">
				<!-- eslint-disable-next-line svelte/no-at-html-tags -- a build-time Tabler icon, not user content -->
				{@html quoteIcon}
			</span>
			<div class="snippets-page__header-copy">
				<Breadcrumbs
					items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: 'Snippets' }]}
				/>
				<h1>Snippets</h1>
				<p>Reusable text your team can drop into any conversation reply.</p>
			</div>
			<div class="snippets-page__header-actions">
				<Button onclick={() => (dialogState = { mode: 'create' })}>New snippet</Button>
			</div>
		</header>

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
					<DataTable
						variant="card"
						{columns}
						{items}
						rowId={(item) => item.id}
						caption="Snippets"
					>
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
	.snippets-page__header {
		display: flex;
		align-items: flex-start;
		gap: 18px;
		margin-top: 16px;
	}
	.snippets-page__header-icon {
		display: grid;
		flex: 0 0 auto;
		place-items: center;
		width: 60px;
		height: 60px;
		margin-top: 4px;
		border-radius: 18px;
		color: var(--color-text--reverse);
		background: var(--color-task);
		box-shadow: 0 6px 16px color-mix(in srgb, var(--color-task) 35%, transparent);
	}
	.snippets-page__header-icon :global(svg) {
		width: 28px;
		height: 28px;
	}
	.snippets-page__header-copy {
		flex: 1;
		min-width: 0;
	}
	.snippets-page__header-copy :global(.breadcrumbs) {
		margin-bottom: 4px;
		font-size: 13px;
		font-weight: 600;
	}
	.snippets-page__header-copy :global(.breadcrumbs a svg) {
		display: none;
	}
	.snippets-page__header h1 {
		margin: 0;
		color: var(--color-heading);
		font-size: 36px;
		font-weight: 900;
		letter-spacing: -1.2px;
		line-height: var(--typography--lineHeight-tight);
	}
	.snippets-page__header p {
		margin: var(--space-smaller) 0 0;
		color: var(--color-text--secondary);
		font-size: 14px;
		font-weight: 500;
		line-height: var(--typography--lineHeight-large);
	}
	.snippets-page__header-actions {
		display: flex;
		flex: 0 0 auto;
		align-items: center;
		align-self: flex-end;
		gap: 10px;
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

	@media (max-width: 639px) {
		.snippets-page__header {
			flex-wrap: wrap;
		}
	}
</style>
