<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
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
	import paperclipIcon from '@tabler/icons/outline/paperclip.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import photoIcon from '@tabler/icons/outline/photo.svg?raw';
	import documentIcon from '@tabler/icons/outline/file-text.svg?raw';
	import clientIcon from '@tabler/icons/outline/user.svg?raw';
	import recordIcon from '@tabler/icons/outline/folder.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';
	import shieldIcon from '@tabler/icons/outline/shield-check.svg?raw';
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
	//
	// mode 'select' (Files and Media Part 6E) is the same browsing UI with no record to attach to yet -- the
	// message composer uses it to pick a File before a message exists. It drops the "record" section and the
	// inline uploader (reuse only, per Jafar's 2026-09-22 call) and hands the picked Files back through
	// onSelected instead of calling attach_file_to_record itself.
	let {
		open,
		mode = 'attach',
		entityType,
		entityId,
		recordLabel = '',
		clientId = null,
		clientLabel = null,
		canManageRecord = false,
		onClose,
		onAttached,
		onUploaded,
		onSelected
	}: {
		open: boolean;
		mode?: 'attach' | 'select';
		/** The record being attached to. Required in 'attach' mode; unused in 'select' mode. */
		entityType?: FileEntityType;
		entityId?: string;
		/** What to call that record in the first section, e.g. "On this job". */
		recordLabel?: string;
		/** The record's customer, when it has one. Gives the second section its files. */
		clientId?: string | null;
		clientLabel?: string | null;
		/** The record's own write permission, the same one that let this dialog open. Uploading straight to
		 * this record follows it even for someone without the library's own files.manage. Ignored in 'select'
		 * mode, which never uploads. */
		canManageRecord?: boolean;
		onClose: () => void;
		/** Called after a successful attach, so the record's own file list can refresh. 'attach' mode only. */
		onAttached?: (fileIds: string[]) => void;
		/** Called once per file uploaded from inside the picker, which joins its record once it is checked. */
		onUploaded?: (fileId: string) => void;
		/** 'select' mode only: called with the chosen Files once the user confirms. */
		onSelected?: (files: FileListItem[]) => void;
	} = $props();

	const queryClient = useQueryClient();
	const uid = $props.id();

	type Section = { id: string; label: string; filters: FileListFilters };

	// Record and customer first, then the library narrowing from most recent to everything — the order the
	// behavior contract fixes. Every section asks for attachable files only: a file still being checked
	// cannot go on a record, so offering it would be offering a button that has to refuse.
	const sections = $derived<Section[]>([
		...(mode === 'attach' && entityType && entityId
			? [
					{
						id: 'record',
						label: recordLabel,
						filters: {
							view: 'on_record' as const,
							folderId: '',
							search: '',
							entityType,
							entityId,
							attachable: true
						}
					}
				]
			: []),
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

	// svelte-ignore state_referenced_locally
	let sectionId = $state(mode === 'select' ? (clientId ? 'client' : 'recent') : 'record');
	let search = $state('');
	let debouncedSearch = $state('');
	let selected = $state<string[]>([]);
	let selectedRecords = $state<Record<string, FileListItem>>({});
	const pickedFiles = $derived(
		selected.map((id) => selectedRecords[id]).filter((file): file is FileListItem => Boolean(file))
	);
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
		queryKey: [...filesListKey(attachedFilters), 'attached-lookup'],
		queryFn: () => fetchFiles(attachedFilters),
		enabled: open && mode === 'attach' && Boolean(entityType && entityId)
	}));

	const files = $derived(filesQuery.data?.pages.flatMap((page) => page.files) ?? []);
	// The library's own can_manage, or this record's own write right -- either opens the Upload button, the
	// same "record's permission, not the library's" rule /api/files/links already applies to attaching.
	// 'select' mode never uploads: it only reuses what is already checked and available.
	const canUpload = $derived(
		mode === 'attach' && (canManageRecord || (filesQuery.data?.pages[0]?.can_manage ?? false))
	);
	const refused = $derived((filesQuery.error as FileReadError | null)?.status === 403);
	const alreadyAttached = $derived(
		new Set((attachedQuery.data?.files ?? []).map((file) => file.id))
	);
	const recordTone = $derived(
		entityType && ['job', 'visit', 'quote', 'invoice', 'request', 'client'].includes(entityType)
			? entityType === 'visit'
				? 'job'
				: entityType
			: 'inactive'
	);
	const isSearching = $derived(debouncedSearch.length > 0);

	function toggle(file: FileListItem) {
		if (attaching || alreadyAttached.has(file.id)) return;
		selectedRecords[file.id] = file;
		selected = selected.includes(file.id)
			? selected.filter((id) => id !== file.id)
			: [...selected, file.id];
	}

	async function submit() {
		if (attaching || selected.length === 0) return;
		if (mode === 'select') {
			const picked = pickedFiles;
			onSelected?.(picked);
			selected = [];
			onClose();
			return;
		}
		if (!entityType || !entityId) return;
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
	function handleUploaded(fileId: string) {
		uploadedHere += 1;
		// The record it was uploaded from is the file's origin, so it joins that record by itself the moment
		// the check finishes. The caller is told so its own list can wait for it rather than look empty.
		onUploaded?.(fileId);
		void queryClient.invalidateQueries({ queryKey: ['files', 'list'] });
	}

	function handleClose() {
		if (attaching) return;
		selectedRecords = {};
		selected = [];
		attachError = '';
		refusals = [];
		uploadedHere = 0;
		onClose();
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog
	{open}
	title={mode === 'select' ? 'Attach a file' : 'Add files'}
	icon={paperclipIcon}
	iconTone="inactive"
	subtitle={recordLabel || undefined}
	size="large"
	onClose={handleClose}
>
	<div class="file-picker">
		<nav class="file-picker__sections" aria-label="Where to look">
			{#each sections as item (item.id)}
				{#if item.id === 'record'}<span class="file-picker__section-heading">On this record</span
					>{/if}
				{#if item.id === 'recent'}<span class="file-picker__section-heading">Library</span>{/if}
				<button
					type="button"
					class="file-picker__section"
					class:file-picker__section--active={sectionId === item.id}
					aria-current={sectionId === item.id ? 'true' : undefined}
					onclick={() => (sectionId = item.id)}
				>
					<IconTile
						icon={item.id === 'client'
							? clientIcon
							: item.id === 'record'
								? recordIcon
								: item.id === 'recent'
									? clockIcon
									: item.id === 'photos'
										? photoIcon
										: item.id === 'documents'
											? documentIcon
											: filesIcon}
						tone={item.id === 'client' ? 'client' : item.id === 'record' ? recordTone : 'inactive'}
						size={24}
					/>{item.label || 'On this record'}
				</button>
			{/each}
		</nav>
		<div class="file-picker__content">
			<div class="file-picker__toolbar">
				<div class="file-picker__search">
					<SearchInput
						id={`${uid}-search`}
						bind:value={search}
						placeholder="Search files, clients, addresses, job or quote numbers"
					/>
				</div>
				{#if canUpload}
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

			{#if canUpload}
				<FileUploader
					bind:this={uploader}
					originType={entityType}
					originId={entityId}
					onUploaded={handleUploaded}
				/>
				{#if uploadedHere > 0}
					<p class="file-picker__note">
						<span aria-hidden="true">{@html shieldIcon}</span>
						{uploadedHere === 1 ? 'That file is' : 'Those files are'} in your library now. As soon as
						the safety check finishes {uploadedHere === 1 ? 'it' : 'they'} can be ticked here and added
						to this record.
					</p>
				{/if}
			{/if}

			{#if refused}<EmptyState
					icon={lockIcon}
					title="You do not have access to the file library"
					description="You can still upload a file straight to this record. Ask an owner or admin if you need to pick from the whole library."
				/>
			{:else if filesQuery.isPending}
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
										signedSrc={file.thumb_url}
									/>
									{#if added}<span class="file-picker__already"
											><span>{@html checkIcon}Already added</span></span
										>{:else}<span
											class="file-picker__mark"
											class:file-picker__mark--picked={picked}
											aria-hidden="true"
											>{#if picked}{@html checkIcon}{/if}</span
										>{/if}
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
					count={files.length}
					recordName="files"
					recordColor="inactive"
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
		</div>
	</div>
	{#snippet footer()}
		<div class="file-picker__footer">
			<div class="file-picker__tray">
				<strong>{selected.length} picked</strong>{#each pickedFiles as file (file.id)}<div
						class="file-picker__picked"
					>
						<FileThumb
							fileId={file.id}
							displayName={file.display_name}
							mimeType={file.mime_type}
							kind={file.kind}
							processingState={file.processing_state}
							hasThumbnail={file.has_thumbnail}
							signedSrc={file.thumb_url}
							size="row"
						/><button
							type="button"
							aria-label={`Unpick ${file.display_name}`}
							disabled={attaching}
							onclick={() => (selected = selected.filter((id) => id !== file.id))}
							>{@html xIcon}</button
						>
					</div>{/each}
			</div>
			<Button variant="secondary" disabled={attaching} onclick={handleClose}>Cancel</Button>
			<Button loading={attaching} disabled={selected.length === 0} onclick={submit}
				>{@html checkIcon}{mode === 'select' ? 'Attach' : 'Add'}
				{selected.length || ''}
				{selected.length === 1 ? 'file' : 'files'}</Button
			>
		</div>
	{/snippet}
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

	@media (max-width: 767px) {
		.file-picker__grid {
			grid-template-columns: repeat(2, minmax(0, 1fr));
			max-height: none;
		}
	}

	.file-picker {
		display: grid;
		grid-template-columns: 220px minmax(0, 1fr);
		gap: 0;
		margin: calc(-1 * var(--space-medium));
	}
	.file-picker__sections {
		display: flex;
		flex-direction: column;
		gap: 2px;
		overflow-x: hidden;
		background: var(--color-surface--background--subtle);
		border-right: var(--border-base) solid var(--color-border);
		padding: var(--space-base) var(--space-slim);
	}
	.file-picker__section-heading {
		padding: var(--space-small) var(--space-small) 6px;
		font-size: var(--typography--fontSize-overline);
		font-weight: 600;
		letter-spacing: 0.6px;
		text-transform: uppercase;
		color: var(--color-text--secondary);
	}
	.file-picker__section {
		display: flex;
		align-items: center;
		gap: 10px;
		height: 40px;
		border: var(--border-base) solid transparent;
		border-radius: var(--radius-base);
		padding: 0 var(--space-small);
		background: transparent;
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
		font-weight: 500;
		text-align: left;
		white-space: normal;
	}
	.file-picker__section--active {
		background: var(--color-surface);
		border-color: var(--color-border--interactive);
		box-shadow: var(--shadow-button);
		font-weight: 600;
		color: var(--color-heading);
	}
	.file-picker__content {
		padding: var(--space-medium);
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		min-width: 0;
	}
	.file-picker__grid {
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-slim);
		max-height: none;
		padding: 0;
	}
	.file-picker__tile {
		border: 0;
		padding: 0;
		gap: var(--space-small);
		background: transparent;
	}
	.file-picker__tile--picked {
		box-shadow: none;
	}
	.file-picker__tile--picked .file-picker__tile-thumb {
		box-shadow: 0 0 0 2px var(--color-interactive);
		border-radius: var(--radius-base);
	}
	.file-picker__tile-thumb {
		width: 100%;
		height: 128px;
		:global(.file-thumb) {
			width: 100%;
			height: 100%;
			aspect-ratio: auto;
		}
	}
	.file-picker__mark {
		left: var(--space-small);
		right: auto;
		top: var(--space-small);
		border-radius: var(--radius-tile-small);
		border: 1.5px solid var(--color-border--interactive);
		background: var(--color-surface);
		color: var(--color-text--reverse);
		box-sizing: border-box;
	}
	.file-picker__mark--picked {
		background: var(--color-interactive);
		border-color: var(--color-interactive);
	}
	.file-picker__already {
		position: absolute;
		inset: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 6px;
		background: color-mix(in srgb, var(--color-surface) 72%, transparent);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		:global(svg) {
			width: 14px;
			height: 14px;
			color: var(--color-success);
		}
	}
	.file-picker__tile-name {
		max-width: 100%;
		font-size: var(--typography--fontSize-label);
	}
	.file-picker__tile-meta {
		font-size: var(--typography--fontSize-small);
	}
	.file-picker__note {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		font-size: var(--typography--fontSize-label);
		:global(svg) {
			width: 16px;
			height: 16px;
			flex-shrink: 0;
			color: var(--color-informative);
		}
	}
	.file-picker__footer {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		width: 100%;
	}
	.file-picker__tray {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		flex: 1;
		min-width: 0;
		flex-wrap: wrap;
		strong {
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
			color: var(--color-heading);
			white-space: nowrap;
		}
	}
	.file-picker__picked {
		position: relative;
		button {
			display: grid;
			place-items: center;
			position: absolute;
			top: -5px;
			right: -5px;
			width: 18px;
			height: 18px;
			padding: 0;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			background: var(--color-surface);
			color: var(--color-icon);
			cursor: pointer;
			:global(svg) {
				width: 10px;
				height: 10px;
			}
		}
		button:hover {
			background: var(--color-surface--hover);
		}
		button:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}
	@media (max-width: 767px) {
		.file-picker {
			grid-template-columns: 1fr;
		}
		.file-picker__sections {
			flex-direction: row;
			overflow-x: auto;
			border-right: 0;
			border-bottom: var(--border-base) solid var(--color-border);
		}
		.file-picker__section-heading {
			display: none;
		}
		.file-picker__section {
			white-space: nowrap;
		}
		.file-picker__grid {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		.file-picker__footer {
			flex-wrap: wrap;
		}
		.file-picker__tray {
			flex-basis: 100%;
		}
	}
	.file-picker__already > span {
		display: flex;
		align-items: center;
		gap: 6px;
		padding: var(--space-smaller) 10px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-circle);
		background: var(--color-surface);
	}
</style>
