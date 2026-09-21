<script lang="ts">
	import { createInfiniteQuery, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import FileThumb from './FileThumb.svelte';
	import FileUploader from './FileUploader.svelte';
	import filesIcon from '@tabler/icons/outline/files.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import uploadIcon from '@tabler/icons/outline/upload.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import {
		attachFilesToRecord,
		fetchFiles,
		filesListKey,
		formatFileSize,
		formatFileType,
		type FileEntityType,
		type FileListFilters,
		type FileListItem,
		type FileListPage,
		type FileReadError
	} from '$lib/files/api';
	import { FILE_PICKER_ACCEPT } from '$lib/files/allowlist';

	// "Attach existing file", reused by every record that can hold one. The order of its sections is the
	// approved contract's, and it is the whole point of the component: what is already on this job or this
	// customer is what a contractor reaches for first, so it leads, and the rest of the library follows.
	//
	// Nothing here copies a file. Attaching is one more use of one stored object, which is why the same photo
	// can sit on a quote, a job and an invoice without costing three uploads.
	let {
		open,
		entityType,
		entityId,
		recordLabel,
		clientId = null,
		clientLabel = null,
		onClose,
		onAttached
	}: {
		open: boolean;
		/** The record being attached to. */
		entityType: FileEntityType;
		entityId: string;
		/** What to call that record in the first section, e.g. "On this job". */
		recordLabel: string;
		/** The record's customer, when it has one. Gives the second section its files. */
		clientId?: string | null;
		clientLabel?: string | null;
		onClose: () => void;
		/** Called after a successful attach, so the record's own file list can refresh. */
		onAttached?: (fileIds: string[]) => void;
	} = $props();

	const queryClient = useQueryClient();
	const uid = $props.id();

	type Section = { id: string; label: string; filters: FileListFilters };

	// Record and customer first, then the library narrowing from most recent to everything — the order the
	// behavior contract fixes. Every section asks for attachable files only: a file still being checked
	// cannot go on a record, so offering it would be offering a button that has to refuse.
	const sections = $derived<Section[]>([
		{
			id: 'record',
			label: recordLabel,
			filters: {
				view: 'on_record',
				folderId: '',
				search: '',
				entityType,
				entityId,
				attachable: true
			}
		},
		...(clientId && clientLabel
			? [
					{
						id: 'client',
						label: clientLabel,
						filters: {
							view: 'on_record' as const,
							folderId: '',
							search: '',
							entityType: 'client' as const,
							entityId: clientId,
							attachable: true
						}
					}
				]
			: []),
		{
			id: 'recent',
			label: 'Recent',
			filters: { view: 'recent', folderId: '', search: '', attachable: true }
		},
		{
			id: 'photos',
			label: 'Photos',
			filters: { view: 'photos', folderId: '', search: '', attachable: true }
		},
		{
			id: 'documents',
			label: 'Documents',
			filters: { view: 'documents', folderId: '', search: '', attachable: true }
		},
		{
			id: 'all',
			label: 'All files',
			filters: { view: 'all', folderId: '', search: '', attachable: true }
		}
	]);

	let sectionId = $state('record');
	let search = $state('');
	let debouncedSearch = $state('');
	let selected = $state<string[]>([]);
	let attaching = $state(false);
	let attachError = $state('');
	let refusals = $state<{ file_id: string; reason: string }[]>([]);

	$effect(() => {
		const value = search;
		const handle = setTimeout(() => (debouncedSearch = value), 300);
		return () => clearTimeout(handle);
	});

	const section = $derived(sections.find((item) => item.id === sectionId) ?? sections[0]);
	const filters = $derived<FileListFilters>({ ...section.filters, search: debouncedSearch });

	// Off until the dialog is open: a picker nobody has opened must not cost a request, and reopening it
	// paints from the cache TanStack kept.
	const filesQuery = createInfiniteQuery(() => ({
		queryKey: filesListKey(filters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) => fetchFiles(filters, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage: FileListPage) => lastPage.next_cursor ?? undefined,
		enabled: open
	}));

	// What is already on this record, so a file the contractor has plainly attached before reads as "Added"
	// instead of tempting them to attach it twice. Attaching is idempotent underneath, so a file past this
	// first page is never a wrong answer — only a missing badge.
	const attachedFilters = $derived<FileListFilters>({
		view: 'on_record',
		folderId: '',
		search: '',
		entityType,
		entityId
	});
	const attachedQuery = createQuery(() => ({
		queryKey: filesListKey(attachedFilters),
		queryFn: () => fetchFiles(attachedFilters),
		enabled: open
	}));

	const files = $derived(filesQuery.data?.pages.flatMap((page) => page.files) ?? []);
	const canManage = $derived(filesQuery.data?.pages[0]?.can_manage ?? false);
	const refused = $derived((filesQuery.error as FileReadError | null)?.status === 403);
	const alreadyAttached = $derived(
		new Set((attachedQuery.data?.files ?? []).map((file) => file.id))
	);
	const isSearching = $derived(debouncedSearch.length > 0);

	function toggle(file: FileListItem) {
		if (alreadyAttached.has(file.id)) return;
		selected = selected.includes(file.id)
			? selected.filter((id) => id !== file.id)
			: [...selected, file.id];
	}

	async function submit() {
		if (attaching || selected.length === 0) return;
		attaching = true;
		attachError = '';
		refusals = [];
		try {
			const result = await attachFilesToRecord(selected, entityType, entityId);
			refusals = result.refused;
			// Every list is now potentially wrong: the file's usage count went up, and "Not attached" may
			// have lost a row. Cheaper to be right about than to work out which keys changed.
			void queryClient.invalidateQueries({ queryKey: ['files', 'list'] });
			void queryClient.invalidateQueries({ queryKey: ['files', 'detail'] });
			onAttached?.(result.attached);
			if (result.refused.length === 0) {
				selected = [];
				onClose();
				return;
			}
			// Some went on and some did not. The ones that did are dropped from the selection so pressing the
			// button again retries only what actually failed.
			selected = selected.filter((id) => !result.attached.includes(id));
		} catch (error) {
			attachError = error instanceof Error ? error.message : 'Those files could not be attached.';
		} finally {
			attaching = false;
		}
	}

	// --- Uploading from inside the picker ------------------------------------------------------------------

	let uploader = $state<ReturnType<typeof FileUploader> | undefined>();
	let fileInputEl = $state<HTMLInputElement | undefined>();
	let uploadedHere = $state(0);

	function pickFiles(list: FileList | null) {
		uploader?.addFiles(list);
		if (fileInputEl) fileInputEl.value = '';
	}

	// A new upload joins the library straight away, but it cannot go on a record until it has been checked --
	// so it appears in this list, with that status, and is attachable the moment the check finishes.
	function handleUploaded() {
		uploadedHere += 1;
		void queryClient.invalidateQueries({ queryKey: ['files', 'list'] });
	}

	function handleClose() {
		selected = [];
		attachError = '';
		refusals = [];
		uploadedHere = 0;
		onClose();
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog {open} title="Add files" size="large" onClose={handleClose}>
	{#if refused}
		<EmptyState
			icon={lockIcon}
			title="You do not have access to the file library"
			description="You can still upload a file straight to this record. Ask an owner or admin if you need to pick from the whole library."
		/>
	{:else}
		<div class="file-picker">
			<div class="file-picker__toolbar">
				<div class="file-picker__search">
					<SearchInput
						id={`${uid}-search`}
						bind:value={search}
						placeholder="Search files, clients, addresses, job or quote numbers"
					/>
				</div>
				{#if canManage}
					<input
						bind:this={fileInputEl}
						type="file"
						multiple
						accept={FILE_PICKER_ACCEPT}
						class="file-picker__file-input"
						id={`${uid}-upload`}
						onchange={(event) => pickFiles((event.currentTarget as HTMLInputElement).files)}
					/>
					<Button variant="secondary" size="small" onclick={() => fileInputEl?.click()}>
						<span class="file-picker__button-icon" aria-hidden="true">{@html uploadIcon}</span
						>Upload
					</Button>
				{/if}
			</div>

			<nav class="file-picker__sections" aria-label="Where to look">
				{#each sections as item (item.id)}
					<button
						type="button"
						class="file-picker__section"
						class:file-picker__section--active={sectionId === item.id}
						aria-current={sectionId === item.id ? 'true' : undefined}
						onclick={() => (sectionId = item.id)}
					>
						{item.label}
					</button>
				{/each}
			</nav>

			{#if canManage}
				<FileUploader originType={entityType} originId={entityId} onUploaded={handleUploaded} />
				{#if uploadedHere > 0}
					<p class="file-picker__note">
						{uploadedHere === 1 ? 'That file is' : 'Those files are'} in your library now. As soon as
						the safety check finishes {uploadedHere === 1 ? 'it' : 'they'} can be ticked here and added
						to this record.
					</p>
				{/if}
			{/if}

			{#if filesQuery.isPending}
				<LoadingSkeleton variant="card" label="Loading files" rows={3} />
			{:else if filesQuery.isError}
				<ErrorState
					description="Your files could not be loaded. Try again."
					retry={() => filesQuery.refetch()}
				/>
			{:else if files.length === 0}
				<EmptyState
					icon={filesIcon}
					title={isSearching ? 'No matching files' : 'Nothing here yet'}
					description={isSearching
						? 'Try a different word, a client name, an address, or a job or quote number.'
						: sectionId === 'record' || sectionId === 'client'
							? 'Nothing has been attached here yet. Look in Recent or All files, or upload something new.'
							: 'Files that have finished their safety check show up here.'}
				/>
			{:else}
				<ul class="file-picker__grid">
					{#each files as file (file.id)}
						{@const added = alreadyAttached.has(file.id)}
						{@const picked = selected.includes(file.id)}
						<li>
							<button
								type="button"
								class="file-picker__tile"
								class:file-picker__tile--picked={picked}
								class:file-picker__tile--added={added}
								aria-pressed={added ? undefined : picked}
								disabled={added}
								onclick={() => toggle(file)}
							>
								<span class="file-picker__tile-thumb">
									<FileThumb
										fileId={file.id}
										displayName={file.display_name}
										mimeType={file.mime_type}
										kind={file.kind}
										processingState={file.processing_state}
										hasThumbnail={file.has_thumbnail}
									/>
									{#if added || picked}
										<span class="file-picker__mark" aria-hidden="true">{@html checkIcon}</span>
									{/if}
								</span>
								<span class="file-picker__tile-name">{file.display_name}</span>
								<span class="file-picker__tile-meta">
									{#if added}
										Already added
									{:else}
										{formatFileType(file.mime_type, file.display_name)} · {formatFileSize(
											file.size_bytes
										)}
									{/if}
								</span>
							</button>
						</li>
					{/each}
				</ul>

				<ListLoadMore
					hasNextPage={filesQuery.hasNextPage}
					isFetchingNextPage={filesQuery.isFetchingNextPage}
					onLoadMore={() => filesQuery.fetchNextPage()}
					endLabel="That is every file here."
				/>
			{/if}

			{#if attachError}<p class="file-picker__error" role="alert">{attachError}</p>{/if}
			{#each refusals as refusal (refusal.file_id)}
				<p class="file-picker__error" role="alert">{refusal.reason}</p>
			{/each}

			<div class="file-picker__actions">
				<Button variant="secondary" variation="subtle" onclick={handleClose}>Cancel</Button>
				<Button loading={attaching} disabled={selected.length === 0} onclick={submit}>
					{selected.length <= 1 ? 'Add file' : `Add ${selected.length} files`}
				</Button>
			</div>
		</div>
	{/if}
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.file-picker {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.file-picker__toolbar {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}
	.file-picker__search {
		flex: 1;
		min-width: 0;
	}
	.file-picker__file-input {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
	}
	.file-picker__button-icon {
		display: inline-flex;
		margin-right: var(--space-smaller);

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}

	.file-picker__sections {
		display: flex;
		gap: var(--space-smaller);
		overflow-x: auto;
	}
	.file-picker__section {
		flex: 0 0 auto;
		padding: var(--space-smaller) var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		color: var(--color-text);
		background: var(--color-surface);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		white-space: nowrap;
		cursor: pointer;

		&:hover {
			border-color: var(--color-border--interactive);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&--active {
			border-color: var(--color-interactive);
			color: var(--color-interactive);
			background: var(--color-surface--active);
		}
	}

	.file-picker__grid {
		display: grid;
		// Smaller than the library's own tiles: this is a chooser inside a dialog, so more of the library
		// should be visible at once than on a page built for reading names.
		grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
		gap: var(--space-base);
		max-height: 46vh;
		overflow-y: auto;
		list-style: none;
	}
	.file-picker__tile {
		display: flex;
		width: 100%;
		flex-direction: column;
		gap: var(--space-smaller);
		padding: var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		text-align: start;
		cursor: pointer;

		&:hover {
			border-color: var(--color-border--interactive);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&--picked {
			border-color: var(--color-interactive);
			box-shadow: var(--shadow-low);
		}
		&--added {
			background: var(--color-surface--background);
			cursor: default;
		}
	}
	.file-picker__tile-thumb {
		position: relative;
		display: block;
	}
	.file-picker__mark {
		position: absolute;
		top: var(--space-smaller);
		right: var(--space-smaller);
		display: grid;
		width: 22px;
		height: 22px;
		place-items: center;
		border-radius: var(--radius-circle);
		color: var(--color-surface);
		background: var(--color-interactive);

		:global(svg) {
			display: block;
			width: 14px;
			height: 14px;
		}
	}
	.file-picker__tile--added .file-picker__mark {
		background: var(--color-disabled);
	}
	.file-picker__tile-name {
		overflow: hidden;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.file-picker__tile-meta {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
	}

	.file-picker__note {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.file-picker__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.file-picker__actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
	}

	@media (max-width: 767px) {
		.file-picker__grid {
			grid-template-columns: repeat(2, minmax(0, 1fr));
			max-height: none;
		}
	}
</style>
