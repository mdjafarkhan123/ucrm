<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { onDestroy } from 'svelte';
	import AttachmentSurface from '$lib/components/collaboration/AttachmentSurface.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import Lightbox, { type LightboxItem } from '$lib/components/ui/Lightbox.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import FilePicker from './FilePicker.svelte';
	import FileThumb from './FileThumb.svelte';
	import {
		detachFileFromRecord,
		downloadFile,
		fetchFiles,
		fileImageUrl,
		filesListKey,
		formatFileSize,
		type FileEntityType,
		type FileListFilters,
		type FileListItem
	} from '$lib/files/api';
	import paperclipIcon from '@tabler/icons/outline/paperclip.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import downloadIcon from '@tabler/icons/outline/download.svg?raw';
	import linkOffIcon from '@tabler/icons/outline/link-off.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	// A record's files, read from the central catalog rather than from a pile of rows belonging to this one
	// record. What it draws is every File currently linked to this record, so a photo the office has also
	// put on the job shows in both places and is stored once.
	//
	// Nothing is staged here, and that is deliberate rather than an exception to the page's save bar: both
	// ways of adding a file happen inside the picker dialog, which carries its own button, and removing one
	// is confirmed in its own dialog. The page's bar has nothing to wait for.
	let {
		entityType,
		entityId,
		/** How to name this record in a sentence, e.g. "this client". */
		recordLabel,
		/** The picker's first section heading, e.g. "On this client". */
		pickerLabel = `On ${recordLabel}`,
		clientId = null,
		clientLabel = null,
		canManage = true,
		title = 'Files',
		surface = 'rail'
	}: {
		entityType: FileEntityType;
		entityId: string;
		recordLabel: string;
		pickerLabel?: string;
		clientId?: string | null;
		clientLabel?: string | null;
		/** May add and remove files here. This is the record's own write permission, not a Files one. */
		canManage?: boolean;
		title?: string;
		surface?: 'rail' | 'section';
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	// The same key shape the picker's "already on this record" section uses, so attaching from the picker
	// refreshes this list through the one invalidation it already does.
	const filters = $derived<FileListFilters>({
		view: 'on_record',
		folderId: '',
		search: '',
		entityType,
		entityId
	});

	// Uploads started here that have not appeared yet. A file uploaded from this record joins it by itself
	// the moment the safety check publishes it, so the card waits for it by id and asks the list again every
	// ten seconds until it turns up -- a contractor watching the card should see it arrive rather than have
	// to reload the page.
	let waitingIds = $state<string[]>([]);
	// Bounded on purpose. A check that never finishes -- a stopped worker, a flagged file that will never be
	// published -- must stop costing a request every ten seconds, so the polling gives up after two minutes
	// and the note says so instead of spinning quietly forever.
	let polling = $state(false);
	let pollTimer: ReturnType<typeof setTimeout> | undefined;

	const filesQuery = createQuery(() => ({
		queryKey: filesListKey(filters),
		queryFn: () => fetchFiles(filters),
		refetchInterval: polling ? 10_000 : false
	}));

	const files = $derived(filesQuery.data?.files ?? []);
	const waiting = $derived(waitingIds.filter((id) => !files.some((file) => file.id === id)));

	function noteUpload(fileId: string) {
		waitingIds = [...waitingIds, fileId];
		polling = true;
		clearTimeout(pollTimer);
		pollTimer = setTimeout(() => (polling = false), 120_000);
	}

	onDestroy(() => clearTimeout(pollTimer));

	const photos = $derived(files.filter((file) => file.kind === 'image'));
	const documents = $derived(files.filter((file) => file.kind !== 'image'));

	let pickerOpen = $state(false);
	let removing = $state<FileListItem | null>(null);
	let removeBusy = $state(false);
	let removeError = $state('');
	let actionError = $state('');

	function refresh() {
		void queryClient.invalidateQueries({ queryKey: ['files', 'list'] });
		void queryClient.invalidateQueries({ queryKey: ['files', 'detail'] });
	}

	async function download(file: FileListItem) {
		actionError = '';
		try {
			await downloadFile(file.id);
		} catch (error) {
			actionError = error instanceof Error ? error.message : 'That file could not be downloaded.';
		}
	}

	async function confirmRemove() {
		if (!removing || removeBusy) return;
		removeBusy = true;
		removeError = '';
		try {
			await detachFileFromRecord(removing.id, entityType, entityId);
			removing = null;
			refresh();
			toast.success(`Removed from ${recordLabel}`);
		} catch (error) {
			removeError =
				error instanceof Error ? error.message : 'That file could not be taken off this record.';
		} finally {
			removeBusy = false;
		}
	}

	function menuFor(file: FileListItem) {
		return [
			{ label: 'Download', icon: downloadIcon, onSelect: () => void download(file) },
			...(canManage
				? [
						{
							label: 'Remove from this record',
							icon: linkOffIcon,
							destructive: true,
							onSelect: () => (removing = file)
						}
					]
				: [])
		];
	}

	// --- Photos -------------------------------------------------------------------------------------------

	let lightboxOpen = $state(false);
	let lightboxIndex = $state(0);

	const lightboxItems = $derived<LightboxItem[]>(
		photos.map((file) => ({
			id: file.id,
			src: fileImageUrl(file.id),
			thumbSrc: fileImageUrl(file.id, 'thumb'),
			caption: file.display_name
		}))
	);

	function openLightbox(file: FileListItem) {
		const position = photos.findIndex((entry) => entry.id === file.id);
		if (position === -1) return;
		lightboxIndex = position;
		lightboxOpen = true;
	}

	function downloadFromLightbox(item: LightboxItem) {
		const file = photos.find((entry) => entry.id === item.id);
		if (file) void download(file);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<AttachmentSurface {surface} {title} icon={paperclipIcon} count={files.length}>
	{#snippet actions()}
		{#if canManage}
			<Button size="small" variant="secondary" onclick={() => (pickerOpen = true)}>
				<span class="record-files__button-icon" aria-hidden="true">{@html plusIcon}</span>Add
			</Button>
		{/if}
	{/snippet}

	{#if actionError}
		<p class="record-files__notice" role="alert">{actionError}</p>
	{/if}

	{#if waiting.length > 0}
		<p class="record-files__waiting">
			{waiting.length === 1 ? 'One file is' : `${waiting.length} files are`} being checked for safety.
			{#if polling}
				{waiting.length === 1 ? 'It appears' : 'They appear'} here as soon as that finishes.
			{:else}
				That is taking longer than usual. Reload the page to look again.
			{/if}
		</p>
	{/if}

	{#if filesQuery.isPending}
		<p class="record-files__muted">Loading files…</p>
	{:else if filesQuery.isError}
		<p class="record-files__notice" role="alert">Files could not be loaded.</p>
	{:else if files.length === 0}
		<div class="record-files__empty">
			<span aria-hidden="true">{@html paperclipIcon}</span>
			<p>
				{canManage
					? 'Add photos and documents from your files, or upload new ones.'
					: 'No files yet.'}
			</p>
		</div>
	{:else}
		{#if photos.length > 0}
			<ul class="record-files__photos">
				{#each photos as file (file.id)}
					<li class="record-files__photo">
						<button
							type="button"
							class="record-files__photo-open"
							aria-label={`View ${file.display_name}`}
							onclick={() => openLightbox(file)}
						>
							<FileThumb
								fileId={file.id}
								displayName={file.display_name}
								mimeType={file.mime_type}
								kind={file.kind}
								processingState={file.processing_state}
								hasThumbnail={file.has_thumbnail}
							/>
						</button>
						{#if canManage}
							<button
								type="button"
								class="record-files__photo-remove"
								aria-label={`Remove ${file.display_name} from this record`}
								onclick={() => (removing = file)}
							>
								{@html xIcon}
							</button>
						{/if}
					</li>
				{/each}
			</ul>
		{/if}

		{#if documents.length > 0}
			<ul class="record-files__list">
				{#each documents as file (file.id)}
					<li class="record-files__item">
						<span class="record-files__item-icon">
							<FileThumb
								fileId={file.id}
								displayName={file.display_name}
								mimeType={file.mime_type}
								kind={file.kind}
								processingState={file.processing_state}
								hasThumbnail={file.has_thumbnail}
								size="row"
							/>
						</span>
						<div class="record-files__item-body">
							<span class="record-files__item-name">{file.display_name}</span>
							<span class="record-files__item-meta">
								{formatFileSize(file.size_bytes)}
								{#if file.usage_count > 1}
									· Used in {file.usage_count} places
								{/if}
							</span>
						</div>
						<DropdownMenu triggerLabel="File actions" items={menuFor(file)} />
					</li>
				{/each}
			</ul>
		{/if}
	{/if}
</AttachmentSurface>

{#if pickerOpen}
	<FilePicker
		open={pickerOpen}
		{entityType}
		{entityId}
		recordLabel={pickerLabel}
		{clientId}
		{clientLabel}
		onClose={() => (pickerOpen = false)}
		onAttached={() => refresh()}
		onUploaded={noteUpload}
	/>
{/if}

{#if removing}
	<ConfirmDialog
		open={Boolean(removing)}
		title={`Remove ${removing.display_name}?`}
		confirmLabel="Remove"
		destructive
		loading={removeBusy}
		onConfirm={() => void confirmRemove()}
		onClose={() => {
			removing = null;
			removeError = '';
		}}
	>
		<p>
			This takes the file off {recordLabel}. It stays in your files, and anywhere else it is used
			keeps it.
		</p>
		{#if removeError}<p class="record-files__notice" role="alert">{removeError}</p>{/if}
	</ConfirmDialog>
{/if}

<Lightbox
	open={lightboxOpen}
	items={lightboxItems}
	bind:index={lightboxIndex}
	onClose={() => (lightboxOpen = false)}
	onDownload={downloadFromLightbox}
/>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.record-files {
		&__button-icon {
			display: inline-flex;
			margin-right: var(--space-smaller);

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		&__notice {
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
			font-size: var(--typography--fontSize-small);
		}

		&__waiting {
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
			font-size: var(--typography--fontSize-small);
		}

		&__muted {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__empty {
			display: flex;
			flex-direction: column;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-large);
			border: var(--border-base) dashed var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			text-align: center;

			:global(svg) {
				display: block;
				width: 24px;
				height: 24px;
			}
		}

		// --- Photos ---------------------------------------------------------------------------------
		&__photos {
			display: grid;
			grid-template-columns: repeat(auto-fill, minmax(72px, 1fr));
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__photo {
			position: relative;
			aspect-ratio: 1;
		}

		&__photo-open {
			display: block;
			width: 100%;
			height: 100%;
			overflow: hidden;
			padding: 0;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
			cursor: pointer;
			transition: border-color var(--timing-quick);

			&:hover {
				border-color: var(--color-border--interactive);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__photo-remove {
			position: absolute;
			top: calc(var(--space-smaller) * -1);
			right: calc(var(--space-smaller) * -1);
			display: grid;
			width: 20px;
			height: 20px;
			place-items: center;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			color: var(--color-icon--secondary);
			background: var(--color-surface);
			cursor: pointer;
			opacity: 0;
			transition: opacity var(--timing-quick);

			:global(svg) {
				display: block;
				width: 12px;
				height: 12px;
			}

			&:hover {
				color: var(--color-critical);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		// Touch has no hover, so the remove button is always there on a small screen.
		&__photo:hover &__photo-remove,
		&__photo-remove:focus-visible {
			opacity: 1;
		}

		// --- Documents ------------------------------------------------------------------------------
		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__item {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-small) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}

		&__item-icon {
			display: grid;
			width: 32px;
			height: 32px;
			flex: 0 0 auto;
			place-items: center;
		}

		&__item-body {
			display: flex;
			min-width: 0;
			flex: 1 1 auto;
			flex-direction: column;
			gap: 2px;
		}

		&__item-name {
			overflow: hidden;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__item-meta {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}
	}

	@media (hover: none) {
		.record-files__photo-remove {
			opacity: 1;
		}
	}
</style>
