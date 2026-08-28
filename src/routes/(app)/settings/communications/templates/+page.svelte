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
	import EmailTemplateDialog from '$lib/components/communications/EmailTemplateDialog.svelte';
	import EmailTemplateLibraryDialog from '$lib/components/communications/EmailTemplateLibraryDialog.svelte';
	import { relativeTime, exactTime } from '$lib/collaboration/format';
	import {
		adoptCommunicationEmailTemplateUpdate,
		communicationEmailTemplatesKey,
		deleteCommunicationEmailTemplate,
		fetchCommunicationEmailTemplates,
		EmailTemplateWriteError,
		type CommunicationEmailTemplate,
		type CommunicationEmailTemplateListItem,
		type CommunicationEmailTemplatePage
	} from '$lib/communications/email-templates';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';

	// Settings → Communications → Templates: the organization's own email library, copied from Jafar's
	// platform templates or written from scratch. Owners/admins manage it; `conversations.send` (checked
	// server-side) is enough to read it, matching the composer picker's own gate.
	const queryClient = useQueryClient();
	const toast = getToastManager();

	let search = $state('');
	let debouncedSearch = $state('');
	let folder = $state('');
	let dialogState = $state<{ mode: 'create' | 'update'; template?: CommunicationEmailTemplate } | null>(
		null
	);
	let libraryOpen = $state(false);
	let deleteTarget = $state<CommunicationEmailTemplateListItem | null>(null);
	let deleting = $state(false);
	let adoptingId = $state<string | null>(null);

	$effect(() => {
		const value = search;
		const handle = setTimeout(() => (debouncedSearch = value), 300);
		return () => clearTimeout(handle);
	});

	const filters = $derived({ search: debouncedSearch, folder: folder || undefined });

	const itemsQuery = createInfiniteQuery(() => ({
		queryKey: communicationEmailTemplatesKey(filters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchCommunicationEmailTemplates(filters, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (page: CommunicationEmailTemplatePage) => page.next_cursor ?? undefined,
		staleTime: 30_000
	}));

	const items = $derived(itemsQuery.data?.pages.flatMap((page) => page.items) ?? []);
	const hasFilters = $derived(Boolean(search.trim() || folder));

	// Folder options come from what is already loaded rather than a second endpoint -- same bounded-library
	// reasoning as Snippets.
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
		await queryClient.invalidateQueries({ queryKey: ['communications', 'email-templates'] });
	}

	function itemMenuItems(item: CommunicationEmailTemplateListItem) {
		const menuItems: {
			label: string;
			icon: string;
			onSelect: () => void;
			destructive?: boolean;
			disabled?: boolean;
		}[] = [
			{
				label: 'Edit',
				icon: pencilIcon,
				onSelect: () => (dialogState = { mode: 'update', template: item })
			}
		];
		if (item.update_available) {
			menuItems.push({
				label: 'Adopt update',
				icon: refreshIcon,
				disabled: adoptingId === item.id,
				onSelect: () => void adopt(item)
			});
		}
		menuItems.push({
			label: 'Delete',
			icon: trashIcon,
			destructive: true,
			onSelect: () => (deleteTarget = item)
		});
		return menuItems;
	}

	function templateSaved() {
		const wasUpdate = dialogState?.mode === 'update';
		dialogState = null;
		void invalidate();
		toast.success(wasUpdate ? 'Template saved.' : 'Template added.');
	}

	function templateCopied() {
		libraryOpen = false;
		void invalidate();
		toast.success('Template added to your library.');
	}

	async function adopt(item: CommunicationEmailTemplateListItem) {
		if (adoptingId) return;
		adoptingId = item.id;
		try {
			await adoptCommunicationEmailTemplateUpdate(item.id);
			await invalidate();
			toast.success('Latest version adopted.');
		} catch (cause) {
			toast.error(
				cause instanceof EmailTemplateWriteError ? cause.message : 'That update could not be adopted.'
			);
		} finally {
			adoptingId = null;
		}
	}

	async function confirmDelete() {
		if (!deleteTarget) return;
		deleting = true;
		try {
			await deleteCommunicationEmailTemplate(deleteTarget.id);
			deleteTarget = null;
			await invalidate();
			toast.success('Template deleted.');
		} catch (cause) {
			toast.error(
				cause instanceof EmailTemplateWriteError ? cause.message : 'That template could not be deleted.'
			);
		} finally {
			deleting = false;
		}
	}

	const columns: DataTableColumn[] = [
		{ key: 'name', label: 'Name' },
		{ key: 'subject', label: 'Subject' },
		{ key: 'updated', label: 'Updated' }
	];
</script>

<svelte:head><title>Templates · Communications · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<div class="templates-page">
		<PageHeader
			eyebrow="Communications"
			title="Templates"
			description="Reusable emails your team can send from any conversation."
		>
			{#snippet actions()}
				<Button href={resolve('/settings')} variant="secondary" variation="subtle">
					Back to settings
				</Button>
				<Button variant="secondary" onclick={() => (libraryOpen = true)}>Copy from library</Button>
				<Button onclick={() => (dialogState = { mode: 'create' })}>New template</Button>
			{/snippet}
		</PageHeader>

		{#if itemsQuery.isPending}
			<LoadingSkeleton variant="table" label="Loading Templates" rows={5} />
		{:else if itemsQuery.isError}
			<ErrorState
				description="Templates could not be loaded. Refresh and try again."
				retry={() => itemsQuery.refetch()}
			/>
		{:else}
			<FilterBar onClear={hasFilters ? clearFilters : undefined}>
				<FilterField id="templates-search" label="Search">
					<SearchInput
						id="templates-search"
						bind:value={search}
						placeholder="Search name or subject"
						ariaLabel="Search Templates"
					/>
				</FilterField>
				<FilterField id="templates-folder" label="Folder">
					<Select
						id="templates-folder"
						value={folder}
						onchange={(value) => (folder = value)}
						options={[{ value: '', label: 'All folders' }, ...folderOptions]}
					/>
				</FilterField>
			</FilterBar>

			{#if items.length === 0}
				<EmptyState
					icon={fileTextIcon}
					title={hasFilters ? 'Nothing matches that' : 'No templates yet'}
					description={hasFilters
						? 'Try a different search term or clear your filters.'
						: 'Copy one from the platform library or write your own, and it will be ready in the composer.'}
				>
					{#snippet action()}
						<Button variant="secondary" onclick={() => (libraryOpen = true)}>
							Copy from library
						</Button>
					{/snippet}
				</EmptyState>
			{:else}
				<DataTable {columns} {items} rowId={(item) => item.id} caption="Templates">
					{#snippet row(item: CommunicationEmailTemplateListItem)}
						<th scope="row">
							<div class="templates-page__title">
								<strong>{item.name}</strong>
								{#if item.folder}<Badge size="small">{item.folder}</Badge>{/if}
								{#if item.update_available}
									<Badge size="small" status="warning">Update available</Badge>
								{/if}
							</div>
						</th>
						<td>
							<span class="templates-page__subject">{item.subject}</span>
						</td>
						<td>
							<span title={exactTime(item.updated_at)}>{relativeTime(item.updated_at)}</span>
						</td>
					{/snippet}
					{#snippet rowActions(item: CommunicationEmailTemplateListItem)}
						<DropdownMenu triggerLabel={`Actions for ${item.name}`} items={itemMenuItems(item)} />
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
	<EmailTemplateDialog
		open={true}
		mode={dialogState.mode}
		template={dialogState.template}
		existingFolders={folderOptions.map((option) => option.value)}
		onSaved={templateSaved}
		onClose={() => (dialogState = null)}
	/>
{/if}

{#if libraryOpen}
	<EmailTemplateLibraryDialog
		open={true}
		onCopied={templateCopied}
		onClose={() => (libraryOpen = false)}
	/>
{/if}

<ConfirmDialog
	open={deleteTarget !== null}
	title="Delete this template?"
	tone="critical"
	destructive
	confirmLabel="Delete template"
	loading={deleting}
	onConfirm={() => void confirmDelete()}
	onClose={() => (deleteTarget = null)}
>
	{#if deleteTarget}
		<p>This can't be undone. "{deleteTarget.name}" will no longer be available in the composer.</p>
	{/if}
</ConfirmDialog>

<style lang="scss">
	.templates-page__title {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
	}

	.templates-page__subject {
		display: -webkit-box;
		overflow: hidden;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		-webkit-box-orient: vertical;
		-webkit-line-clamp: 2;
		line-clamp: 2;
	}
</style>
