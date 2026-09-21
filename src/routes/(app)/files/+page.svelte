<script lang="ts">
	import { createInfiniteQuery, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import Lightbox, { type LightboxItem } from '$lib/components/ui/Lightbox.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import FileThumb from '$lib/components/files/FileThumb.svelte';
	import FileDetailsPanel from '$lib/components/files/FileDetailsPanel.svelte';
	import FileUploader from '$lib/components/files/FileUploader.svelte';
	import filesIcon from '@tabler/icons/outline/files.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import uploadIcon from '@tabler/icons/outline/upload.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import {
		createFileFolder,
		downloadFile,
		fetchFileFolders,
		fetchFiles,
		fileDetailKey,
		fileFoldersKey,
		fileImageUrl,
		filesListKey,
		fetchFile,
		formatFileType,
		formatOrigin,
		type FileListItem,
		type FileListPage,
		type FileReadError,
		type FileView
	} from '$lib/files/api';
	import { FILE_PICKER_ACCEPT } from '$lib/files/allowlist';

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const uid = $props.id();

	// The rail. "Shared with customers" and "Videos" are deliberately missing: customer sharing arrives
	// with Part 7 and video is not an accepted upload type yet, so either one would be a view that can
	// only ever be empty — a promise the app cannot keep.
	const SMART_VIEWS: { value: FileView; label: string }[] = [
		{ value: 'all', label: 'All files' },
		{ value: 'recent', label: 'Recent' },
		{ value: 'photos', label: 'Photos' },
		{ value: 'documents', label: 'Documents' },
		{ value: 'not_attached', label: 'Not attached' },
		{ value: 'trash', label: 'Trash' }
	];

	let view = $state<FileView>('all');
	let folderId = $state('');
	let search = $state('');
	let debouncedSearch = $state('');
	let layout = $state<'grid' | 'list'>('grid');
	// The id rather than the row: after a rename or a move the list refetches, and holding the old snapshot
	// would leave the panel showing a name the library no longer agrees with.
	let selectedId = $state('');
	let panelOpen = $state(false);
	let lightboxOpen = $state(false);
	let lightboxIndex = $state(0);
	let downloadError = $state('');

	$effect(() => {
		const value = search;
		const handle = setTimeout(() => (debouncedSearch = value), 300);
		return () => clearTimeout(handle);
	});

	const filters = $derived({ view, folderId, search: debouncedSearch });

	const filesQuery = createInfiniteQuery(() => ({
		queryKey: filesListKey(filters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) => fetchFiles(filters, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage: FileListPage) => lastPage.next_cursor ?? undefined
	}));
	const foldersQuery = createQuery(() => ({
		queryKey: fileFoldersKey,
		queryFn: fetchFileFolders
	}));

	const files = $derived(filesQuery.data?.pages.flatMap((page) => page.files) ?? []);
	const folders = $derived(foldersQuery.data ?? []);
	const refused = $derived((filesQuery.error as FileReadError | null)?.status === 403);
	const isSearching = $derived(debouncedSearch.length > 0);
	const selectedFile = $derived(files.find((file) => file.id === selectedId) ?? null);
	// The first page carries what this member may do, resolved server-side. Every write re-checks it; this
	// only decides whether the Upload button and New folder are on screen at all.
	const canManage = $derived(filesQuery.data?.pages[0]?.can_manage ?? false);

	// Every available photo on screen, so the lightbox's arrows and filmstrip walk the library rather than
	// showing one picture at a time.
	const photos = $derived(
		files.filter((file) => file.kind === 'image' && file.processing_state === 'available')
	);
	const lightboxItems = $derived<LightboxItem[]>(
		photos.map((file) => ({
			id: file.id,
			src: fileImageUrl(file.id),
			thumbSrc: fileImageUrl(file.id, 'thumb'),
			caption: file.display_name
		}))
	);

	function selectView(next: FileView) {
		view = next;
		folderId = '';
		closePanel();
	}
	function selectFolder(id: string) {
		view = 'folder';
		folderId = id;
		closePanel();
	}

	// The panel's query stays off until a file is hovered or focused, then this warms it so the click
	// normally paints from cache. A click that beats the fetch shows the panel's own skeleton.
	function prefetchFile(file: FileListItem) {
		void queryClient.prefetchQuery({
			queryKey: fileDetailKey(file.id),
			queryFn: () => fetchFile(file.id)
		});
	}

	function openPanel(file: FileListItem) {
		selectedId = file.id;
		panelOpen = true;
	}
	function closePanel() {
		panelOpen = false;
	}

	// --- Uploading and folders --------------------------------------------------------------------------

	let uploader = $state<ReturnType<typeof FileUploader> | undefined>();
	let fileInputEl = $state<HTMLInputElement | undefined>();
	let draggingOver = $state(false);
	let folderDialogOpen = $state(false);
	let folderName = $state('');
	let folderSaving = $state(false);
	let folderError = $state('');

	function pickFiles(list: FileList | null) {
		uploader?.addFiles(list);
		if (fileInputEl) fileInputEl.value = '';
	}

	// A file that has reached storage is in the library, still being checked. Refreshing the list is what
	// puts its row on screen with that status, rather than leaving the contractor wondering where it went.
	function handleUploaded() {
		void queryClient.invalidateQueries({ queryKey: ['files', 'list'] });
		void queryClient.invalidateQueries({ queryKey: fileFoldersKey });
	}

	// Only a drag carrying actual files. Dragging selected text or a link across the page is not an upload.
	function carriesFiles(event: DragEvent) {
		return Array.from(event.dataTransfer?.types ?? []).includes('Files');
	}

	function handleDrop(event: DragEvent) {
		if (!canManage || !carriesFiles(event)) return;
		event.preventDefault();
		draggingOver = false;
		pickFiles(event.dataTransfer?.files ?? null);
	}

	async function submitFolder() {
		if (folderSaving) return;
		folderSaving = true;
		folderError = '';
		try {
			const { folder } = await createFileFolder(folderName);
			await queryClient.invalidateQueries({ queryKey: fileFoldersKey });
			folderDialogOpen = false;
			folderName = '';
			toast.success('Folder created');
			selectFolder(folder.id);
		} catch (error) {
			folderError = error instanceof Error ? error.message : 'That folder could not be created.';
		} finally {
			folderSaving = false;
		}
	}

	function openLightbox(file: FileListItem) {
		const index = photos.findIndex((photo) => photo.id === file.id);
		if (index < 0) return;
		lightboxIndex = index;
		lightboxOpen = true;
	}

	async function handleLightboxDownload(item: LightboxItem) {
		downloadError = '';
		try {
			await downloadFile(item.id);
		} catch (error) {
			downloadError = error instanceof Error ? error.message : 'That download did not start.';
		}
	}

	function formatUploadedAt(value: string) {
		return new Date(value).toLocaleDateString(undefined, {
			month: 'short',
			day: 'numeric',
			year: 'numeric'
		});
	}

	function usageLabel(file: FileListItem) {
		if (file.usage_count === 0) return 'Not attached';
		return file.usage_count === 1 ? '1 place' : `${file.usage_count} places`;
	}

	const emptyTitle = $derived.by(() => {
		if (isSearching) return 'No matching files';
		if (view === 'trash') return 'Trash is empty';
		if (view === 'not_attached') return 'Everything is attached';
		if (view === 'folder') return 'This folder is empty';
		if (view === 'photos') return 'No photos yet';
		if (view === 'documents') return 'No documents yet';
		return 'No files yet';
	});
	const emptyDescription = $derived.by(() => {
		if (isSearching)
			return 'Try a different word, a client name, an address, or a job or quote number.';
		if (view === 'trash') return 'Files you move to Trash wait here for 30 days before they go.';
		if (view === 'not_attached')
			return 'Every file in your library is being used by a job, quote or client.';
		if (canManage)
			return 'Photos and documents from your jobs, quotes and clients collect here automatically. You can also press Upload, or drag files onto this page.';
		return 'Photos and documents from your jobs, quotes and clients collect here automatically.';
	});
</script>

<svelte:head><title>Files · Contractor CRM</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<PageContainer variant="fill">
	<PageHeader
		title="Files"
		description="Every photo and document your business has, in one place."
	/>

	{#if refused}
		<EmptyState
			icon={lockIcon}
			title="You do not have access to the file library"
			description="You can still open the photos and documents on the jobs and quotes you work on. Ask an owner or admin if you need the whole library."
		/>
	{:else}
		<div class="files">
			<nav class="files__rail" aria-label="File views">
				<ul class="files__rail-list">
					{#each SMART_VIEWS as smartView (smartView.value)}
						<li>
							<button
								type="button"
								class="files__rail-item"
								class:files__rail-item--active={view === smartView.value}
								aria-current={view === smartView.value ? 'true' : undefined}
								onclick={() => selectView(smartView.value)}
							>
								{smartView.label}
							</button>
						</li>
					{/each}
				</ul>

				<div class="files__rail-heading-row">
					<p class="files__rail-heading">Folders</p>
					{#if canManage}
						<button
							type="button"
							class="files__rail-add"
							aria-label="New folder"
							onclick={() => {
								folderError = '';
								folderDialogOpen = true;
							}}
						>
							{@html plusIcon}
						</button>
					{/if}
				</div>
				{#if folders.length === 0}
					<p class="files__rail-empty">No folders yet.</p>
				{:else}
					<ul class="files__rail-list">
						{#each folders as folder (folder.id)}
							<li>
								<button
									type="button"
									class="files__rail-item"
									class:files__rail-item--active={view === 'folder' && folderId === folder.id}
									aria-current={view === 'folder' && folderId === folder.id ? 'true' : undefined}
									onclick={() => selectFolder(folder.id)}
								>
									<span class="files__rail-item-label">{folder.name}</span>
									<span class="files__rail-count">{folder.file_count}</span>
								</button>
							</li>
						{/each}
					</ul>
				{/if}
			</nav>

			<!-- The drop zone is a convenience layered over the library. The Upload button beside it is the
			     keyboard and screen-reader path to exactly the same thing, so there is nothing to focus here. -->
			<!-- svelte-ignore a11y_no_static_element_interactions -->
			<div
				class="files__main"
				class:files__main--dropping={draggingOver}
				ondragover={(event) => {
					if (!canManage || !carriesFiles(event)) return;
					event.preventDefault();
					draggingOver = true;
				}}
				ondragleave={(event) => {
					// Moving between children fires dragleave on the parent; only a real exit counts.
					if (event.currentTarget.contains(event.relatedTarget as Node | null)) return;
					draggingOver = false;
				}}
				ondrop={handleDrop}
			>
				<div class="files__toolbar">
					<div class="files__toolbar-search">
						<SearchInput
							id="files-search"
							bind:value={search}
							placeholder="Search files, clients, addresses, job or quote numbers"
						/>
					</div>
					<SegmentedControl
						name="files-layout"
						label=""
						size="small"
						bind:value={layout}
						options={[
							{ value: 'grid', label: 'Grid' },
							{ value: 'list', label: 'List' }
						]}
					/>
					{#if canManage}
						<input
							bind:this={fileInputEl}
							type="file"
							multiple
							accept={FILE_PICKER_ACCEPT}
							class="files__file-input"
							id={`${uid}-picker`}
							onchange={(event) => pickFiles((event.currentTarget as HTMLInputElement).files)}
						/>
						<Button size="small" onclick={() => fileInputEl?.click()}>
							<span class="files__button-icon" aria-hidden="true">{@html uploadIcon}</span>Upload
						</Button>
					{/if}
				</div>

				{#if canManage}
					<FileUploader
						bind:this={uploader}
						folderId={view === 'folder' && folderId ? folderId : null}
						onUploaded={handleUploaded}
					/>
				{/if}

				{#if downloadError}
					<p class="files__error" role="alert">{downloadError}</p>
				{/if}

				{#if filesQuery.isPending}
					<LoadingSkeleton variant="card" label="Loading files" rows={4} />
				{:else if filesQuery.isError}
					<ErrorState
						description="Your files could not be loaded. Try again."
						retry={() => filesQuery.refetch()}
					/>
				{:else if files.length === 0}
					<EmptyState icon={filesIcon} title={emptyTitle} description={emptyDescription} />
				{:else if layout === 'grid'}
					<ul class="files__grid">
						{#each files as file (file.id)}
							<li>
								<button
									type="button"
									class="files__tile"
									class:files__tile--selected={panelOpen && selectedFile?.id === file.id}
									onclick={() => openPanel(file)}
									onmouseenter={() => prefetchFile(file)}
									onfocus={() => prefetchFile(file)}
								>
									<FileThumb
										fileId={file.id}
										displayName={file.display_name}
										mimeType={file.mime_type}
										kind={file.kind}
										processingState={file.processing_state}
										hasThumbnail={file.has_thumbnail}
									/>
									<span class="files__tile-name">{file.display_name}</span>
									<span class="files__tile-meta">{usageLabel(file)}</span>
								</button>
							</li>
						{/each}
					</ul>
				{:else}
					<table class="files__table">
						<caption class="files__table-caption">Files</caption>
						<thead>
							<tr>
								<th scope="col">Name</th>
								<th scope="col">Type</th>
								<th scope="col">Folder</th>
								<th scope="col">Came from</th>
								<th scope="col">Uploaded</th>
								<th scope="col">Used in</th>
							</tr>
						</thead>
						<tbody>
							{#each files as file (file.id)}
								<tr
									class:files__row--selected={panelOpen && selectedFile?.id === file.id}
									onmouseenter={() => prefetchFile(file)}
								>
									<th scope="row">
										<button
											type="button"
											class="files__row-name"
											onclick={() => openPanel(file)}
											onfocus={() => prefetchFile(file)}
										>
											<FileThumb
												fileId={file.id}
												displayName={file.display_name}
												mimeType={file.mime_type}
												kind={file.kind}
												processingState={file.processing_state}
												hasThumbnail={file.has_thumbnail}
												size="row"
											/>
											<span class="files__row-name-text">{file.display_name}</span>
										</button>
									</th>
									<td>{formatFileType(file.mime_type, file.display_name)}</td>
									<td>{file.folder_name ?? '—'}</td>
									<td>{formatOrigin(file.origin_type)}</td>
									<td>{formatUploadedAt(file.created_at)}</td>
									<td>{usageLabel(file)}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				{/if}

				{#if files.length > 0}
					<ListLoadMore
						hasNextPage={filesQuery.hasNextPage}
						isFetchingNextPage={filesQuery.isFetchingNextPage}
						onLoadMore={() => filesQuery.fetchNextPage()}
						endLabel="That is every file here."
					/>
				{/if}
			</div>
		</div>
	{/if}
</PageContainer>

<FileDetailsPanel
	file={selectedFile}
	open={panelOpen}
	onClose={closePanel}
	onOpenLightbox={openLightbox}
/>

<Lightbox
	open={lightboxOpen}
	items={lightboxItems}
	bind:index={lightboxIndex}
	onClose={() => (lightboxOpen = false)}
	onDownload={handleLightboxDownload}
/>

<Dialog
	open={folderDialogOpen}
	title="New folder"
	size="small"
	initialFocusId={`${uid}-folder-name`}
	onClose={() => (folderDialogOpen = false)}
>
	<form
		class="files__form"
		onsubmit={(event) => {
			event.preventDefault();
			void submitFolder();
		}}
	>
		<Input
			id={`${uid}-folder-name`}
			label="Folder name"
			bind:value={folderName}
			required
			placeholder="Boiler jobs"
		/>
		<p class="files__hint">
			Folders are just a way to tidy your library. Putting a file in one never changes the jobs,
			quotes or clients it is attached to.
		</p>
		{#if folderError}<p class="files__error" role="alert">{folderError}</p>{/if}
		<div class="files__form-actions">
			<Button variant="secondary" variation="subtle" onclick={() => (folderDialogOpen = false)}>
				Cancel
			</Button>
			<Button type="submit" loading={folderSaving} disabled={!folderName.trim()}>Create</Button>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.files {
		display: grid;
		grid-template-columns: 200px minmax(0, 1fr);
		gap: var(--space-large);
		margin-top: var(--space-large);
	}

	.files__rail {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}
	.files__rail-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		list-style: none;
	}
	.files__rail-item {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		width: 100%;
		padding: var(--space-small) var(--space-slim);
		border: none;
		border-radius: var(--radius-base);
		color: var(--color-text);
		background: transparent;
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		text-align: start;
		cursor: pointer;

		&:hover {
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&--active {
			color: var(--color-interactive);
			background: var(--color-surface--active);
		}
	}
	.files__rail-item-label {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.files__rail-count {
		flex: 0 0 auto;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
	}
	.files__rail-heading-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-smaller);
	}
	.files__rail-add {
		display: grid;
		width: 24px;
		height: 24px;
		flex: 0 0 auto;
		margin-top: var(--space-base);
		place-items: center;
		border: none;
		border-radius: var(--radius-small);
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;

		&:hover {
			color: var(--color-interactive);
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}
	.files__rail-heading {
		margin-top: var(--space-base);
		padding: 0 var(--space-slim);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.files__rail-empty {
		padding: 0 var(--space-slim);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.files__main {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		min-width: 0;
		padding: var(--space-smaller);
		// Reserved whether or not a drag is happening, so the library does not jump sideways when one starts.
		border: var(--border-base) dashed transparent;
		border-radius: var(--radius-base);

		&--dropping {
			border-color: var(--color-border--interactive);
			background: var(--color-surface--hover);
		}
	}
	.files__toolbar {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}
	.files__toolbar-search {
		flex: 1;
		min-width: 0;
	}
	.files__file-input {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
	}
	.files__button-icon {
		display: inline-flex;
		margin-right: var(--space-smaller);

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}
	.files__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.files__hint {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.files__form {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}
	.files__form-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
	}

	.files__grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
		gap: var(--space-large);
		list-style: none;
	}
	.files__tile {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		width: 100%;
		padding: var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		text-align: start;
		cursor: pointer;

		&:hover {
			border-color: var(--color-border--interactive);
			box-shadow: var(--shadow-low);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&--selected {
			border-color: var(--color-interactive);
			box-shadow: var(--shadow-low);
		}
	}
	.files__tile-name {
		overflow: hidden;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.files__tile-meta {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.files__table {
		width: 100%;
		border-collapse: collapse;
		font-size: var(--typography--fontSize-base);

		th,
		td {
			padding: var(--space-small);
			border-bottom: var(--border-base) solid var(--color-border);
			text-align: start;
		}
		thead th {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			text-transform: uppercase;
			letter-spacing: 0.04em;
		}
		tbody tr:hover {
			background: var(--color-surface--hover);
		}
	}
	.files__table-caption {
		position: absolute;
		width: 1px;
		height: 1px;
		margin: -1px;
		padding: 0;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
	}
	.files__row--selected {
		background: var(--color-surface--active);
	}
	.files__row-name {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: 0;
		border: none;
		background: transparent;
		text-align: start;
		cursor: pointer;

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}
	.files__row-name-text {
		color: var(--color-heading);
		font-weight: 600;
	}

	@media (max-width: 767px) {
		.files {
			grid-template-columns: minmax(0, 1fr);
		}
		// The rail becomes one scrolling row of chips above the library rather than a column that eats
		// half a phone screen.
		.files__rail-list {
			flex-direction: row;
			gap: var(--space-smaller);
			overflow-x: auto;
		}
		.files__rail-item {
			width: auto;
			white-space: nowrap;
		}
		.files__grid {
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base);
		}
	}
</style>
