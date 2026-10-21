<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { onDestroy } from 'svelte';
	import AttachmentSurface from '$lib/components/collaboration/AttachmentSurface.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import Lightbox, { type LightboxItem } from '$lib/components/ui/Lightbox.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import FilePicker from './FilePicker.svelte';
	import FileThumb from './FileThumb.svelte';
	import PhotoDescribeDialog from './PhotoDescribeDialog.svelte';
	import {
		detachFileFromRecord,
		downloadFile,
		fetchFile,
		fetchFileLabels,
		fetchFiles,
		fileDetailKey,
		fileLabelsKey,
		listedFileImageUrl,
		SIGNED_IMAGE_REFRESH_MS,
		filesListKey,
		formatFileSize,
		type FileEntityType,
		type FileListFilters,
		type FileListItem
	} from '$lib/files/api';
	import paperclipIcon from '@tabler/icons/outline/paperclip.svg?raw';
	import uploadIcon from '@tabler/icons/outline/upload.svg?raw';
	import downloadIcon from '@tabler/icons/outline/download.svg?raw';
	import unlinkIcon from '@tabler/icons/outline/unlink.svg?raw';
	import alertCircleIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import clockAlertIcon from '@tabler/icons/outline/clock-exclamation.svg?raw';
	import loaderIcon from '@tabler/icons/outline/loader-2.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
	import imagesIcon from '@tabler/icons/outline/library-photo.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';
	import tagIcon from '@tabler/icons/outline/tag.svg?raw';

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
		surface = 'rail',
		compact = false,
		summary = false,
		recordName,
		onChange
	}: {
		/** The record by name ("Job #108"), for the caption pop-up's hint line. */
		recordName?: string;
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
		/** App look: six photos in a grid with a "+N" tile, a quiet count under the title, and an icon-only
		 *  add button. Meant for the rail of a record page drawn with `RecordDetailLayout cards`. */
		compact?: boolean;
		/** App look: say how many photos and files there are under the title instead of a count beside it. */
		summary?: boolean;
		/** Fires after a file is attached to or removed from this record, once the list has refreshed. */
		onChange?: () => void;
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
		refetchInterval: polling ? 10_000 : SIGNED_IMAGE_REFRESH_MS
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
	const PHOTO_TILES = 6;
	const shownPhotos = $derived(compact ? photos.slice(0, PHOTO_TILES) : photos);
	const hiddenPhotoCount = $derived(compact ? Math.max(0, photos.length - PHOTO_TILES) : 0);
	const addedFormat = new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' });

	let pickerOpen = $state(false);
	let removing = $state<FileListItem | null>(null);
	let removeBusy = $state(false);
	let removeError = $state('');
	let actionError = $state('');

	function refresh() {
		void queryClient.invalidateQueries({ queryKey: ['files', 'list'] });
		void queryClient.invalidateQueries({ queryKey: ['files', 'detail'] });
		// A job's or visit's photos are the work report editor's choices.
		void queryClient.invalidateQueries({ queryKey: ['jobs', 'report'] });
		onChange?.();
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

	// "PDF", "Word", "Photo": what a person calls the file, ahead of its size.
	function fileTypeLabel(file: FileListItem) {
		if (file.mime_type === 'application/pdf') return 'PDF';
		if (file.kind === 'image') return 'Photo';
		if (file.kind === 'video') return 'Video';
		const extension = file.display_name.includes('.')
			? file.display_name.split('.').pop()?.toUpperCase()
			: '';
		return extension || 'File';
	}

	// --- Photos -------------------------------------------------------------------------------------------

	// Caption and labels, offered on a job or visit: that is where the crew who took a photo reaches it (they
	// have no File Manager). The server's can_describe decides whether the dialog edits or only shows.
	const offersDescribe = $derived(canManage && (entityType === 'job' || entityType === 'visit'));
	let describing = $state<FileListItem | null>(null);

	// Warm the dialog on hover, so a click paints from cache.
	function prefetchDescribe(file: FileListItem) {
		void queryClient.prefetchQuery({
			queryKey: fileDetailKey(file.id),
			queryFn: () => fetchFile(file.id)
		});
		void queryClient.prefetchQuery({ queryKey: fileLabelsKey, queryFn: fetchFileLabels });
	}

	let lightboxOpen = $state(false);
	let lightboxIndex = $state(0);

	const lightboxItems = $derived<LightboxItem[]>(
		photos.map((file) => ({
			id: file.id,
			src: listedFileImageUrl(file),
			thumbSrc: listedFileImageUrl(file, 'thumb'),
			caption: file.display_name
		}))
	);

	const summaryLine = $derived(
		[
			photos.length > 0 ? `${photos.length} ${photos.length === 1 ? 'photo' : 'photos'}` : '',
			documents.length > 0 ? `${documents.length} ${documents.length === 1 ? 'file' : 'files'}` : ''
		]
			.filter(Boolean)
			.join(' · ')
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
<AttachmentSurface
	{surface}
	{title}
	icon={paperclipIcon}
	count={undefined}
	description={filesQuery.isPending
		? undefined
		: summary || compact
			? summaryLine
			: `${files.length} on this ${entityType.replaceAll('_', ' ')}`}
	flush={compact}
>
	{#snippet actions()}
		{#if canManage}
			<Button size="small" variant="secondary" onclick={() => (pickerOpen = true)}>
				<span class="record-files__button-icon" aria-hidden="true">{@html uploadIcon}</span>Add
			</Button>
		{/if}
	{/snippet}

	{#if actionError}
		<p class="record-files__notice record-files__notice--critical" role="alert">
			<span class="record-files__notice-icon" aria-hidden="true">{@html alertCircleIcon}</span>
			{actionError}
		</p>
	{/if}

	{#if waiting.length > 0}
		<p class="record-files__notice record-files__notice--warning" role="status">
			{#if polling}
				<span class="record-files__notice-icon record-files__notice-icon--spin" aria-hidden="true"
					>{@html loaderIcon}</span
				>
			{:else}
				<span class="record-files__notice-icon" aria-hidden="true">{@html clockAlertIcon}</span>
			{/if}
			<span>
				{waiting.length === 1 ? 'One file is' : `${waiting.length} files are`} being checked for safety.
				{#if polling}
					{waiting.length === 1 ? 'It appears' : 'They appear'} here as soon as that finishes.
				{:else}
					That is taking longer than usual. Reload the page to look again.
				{/if}
			</span>
		</p>
	{/if}

	{#if filesQuery.isPending}
		<div class="record-files__loading" role="status" aria-label="Loading files">
			<div class="record-files__photos">
				{#each [0, 1, 2] as bone (bone)}
					<span class="skeleton record-files__bone-photo"></span>
				{/each}
			</div>
			{#each [0, 1] as bone (bone)}
				<div class="record-files__item">
					<span class="skeleton record-files__bone-thumb"></span>
					<span class="record-files__item-body">
						<span class="skeleton record-files__bone-line"></span>
						<span class="skeleton record-files__bone-line record-files__bone-line--short"></span>
					</span>
				</div>
			{/each}
		</div>
	{:else if filesQuery.isError}
		<div class="record-files__state" role="alert">
			<IconTile icon={alertTriangleIcon} tone="critical" size={32} />
			<p class="record-files__state-title">Files didn't load</p>
			<p class="record-files__state-hint">Check your connection, then try again.</p>
			<Button
				size="small"
				variant="secondary"
				loading={filesQuery.isFetching}
				onclick={() => filesQuery.refetch()}
			>
				{@html refreshIcon}Try again
			</Button>
		</div>
	{:else if files.length === 0}
		{#if canManage}
			<div class="record-files__empty">
				<span class="record-files__empty-icon" aria-hidden="true">{@html imagesIcon}</span>
				<p class="record-files__state-title">No photos or files yet</p>
				<p class="record-files__state-hint">Add photos and documents from your files, or upload new ones.</p>
			</div>
		{:else}
			<div class="record-files__state">
				<IconTile icon={imagesIcon} tone="inactive" size={32} />
				<p class="record-files__state-title">No files yet</p>
				<p class="record-files__state-hint">Photos and documents added here show up for you.</p>
			</div>
		{/if}
	{:else}
		{#if photos.length > 0}
			<ul class="record-files__photos">
				{#each shownPhotos as file, position (file.id)}
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
								signedSrc={file.thumb_url}
							/>
							{#if hiddenPhotoCount > 0 && position === shownPhotos.length - 1}
								<span class="record-files__more" aria-label={`${hiddenPhotoCount} more photos`}>
									+{hiddenPhotoCount}
								</span>
							{/if}
						</button>
						{#if offersDescribe || canManage}
							<span class="record-files__photo-actions">
								{#if offersDescribe}
									<button
										type="button"
										class="record-files__photo-action"
										aria-label={`Caption and labels for ${file.display_name}`}
										title="Caption and labels"
										onpointerenter={() => prefetchDescribe(file)}
										onfocus={() => prefetchDescribe(file)}
										onclick={() => (describing = file)}
									>
										{@html tagIcon}
									</button>
								{/if}
								{#if canManage}
									<button
										type="button"
										class="record-files__photo-action"
										aria-label={`Remove ${file.display_name} from this record`}
										title="Remove"
										onclick={() => (removing = file)}
									>
										{@html xIcon}
									</button>
								{/if}
							</span>
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
								signedSrc={file.thumb_url}
								size="row"
							/>
						</span>
						<div class="record-files__item-body">
							<span class="record-files__item-name">{file.display_name}</span>
							<span class="record-files__item-meta">
								{fileTypeLabel(file)} · {formatFileSize(file.size_bytes)} · {addedFormat.format(
									new Date(file.created_at)
								)}{#if file.usage_count > 1}
									· used in {file.usage_count} places{/if}
							</span>
						</div>
						<DropdownMenu
							triggerLabel="File actions"
							triggerVariant="quiet"
							items={[{ label: 'Download', icon: downloadIcon, onSelect: () => void download(file) }]}
							footer={canManage
								? [
										{
											label: 'Remove from this record',
											icon: unlinkIcon,
											destructive: true,
											onSelect: () => (removing = file)
										}
									]
								: []}
						/>
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
		canManageRecord={canManage}
		onClose={() => (pickerOpen = false)}
		onAttached={() => refresh()}
		onUploaded={noteUpload}
	/>
{/if}

{#if removing}
	<ConfirmDialog
		open={Boolean(removing)}
		title={`Remove ${removing.display_name}?`}
		icon={unlinkIcon}
		tone="critical"
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
		{#if removeError}
			<p class="record-files__remove-error" role="alert">
				<span class="record-files__notice-icon" aria-hidden="true">{@html alertCircleIcon}</span>
				{removeError}
			</p>
		{/if}
	</ConfirmDialog>
{/if}

{#if offersDescribe}
	<PhotoDescribeDialog
		open={Boolean(describing)}
		fileId={describing?.id ?? null}
		fileName={describing?.display_name ?? ''}
		{recordName}
		onClose={() => (describing = null)}
	/>
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
	// Record files card (`files.md`, board `pH9PB`).
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

		// --- Notices --------------------------------------------------------------------------------
		&__notice {
			display: flex;
			align-items: flex-start;
			gap: 10px;
			margin: 0;
			padding: 10px var(--space-slim);
			border: var(--border-base) solid;
			border-radius: var(--radius-base);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
			line-height: var(--typography--lineHeight-large);

			&--warning {
				border-color: var(--color-warning--surface-edge);
				color: var(--color-warning--onSurface);
				background: var(--color-warning--surface);
			}

			&--critical {
				border-color: var(--color-critical--surface-edge);
				color: var(--color-critical--onSurface);
				background: var(--color-critical--surface);

				.record-files__notice-icon {
					color: var(--color-critical);
				}
			}
		}

		&__notice-icon {
			display: inline-flex;
			flex: 0 0 auto;
			padding-top: 1px;

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}

			&--spin :global(svg) {
				animation: record-files-spin 900ms linear infinite;
			}
		}

		&__remove-error {
			display: flex;
			align-items: center;
			gap: 6px;
			margin-top: var(--space-slim);
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			.record-files__notice-icon :global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		// --- States ---------------------------------------------------------------------------------
		&__loading {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__bone-photo {
			height: 92px;
			min-height: 0;
			border-radius: var(--radius-base);
		}

		&__bone-thumb {
			width: 40px;
			height: 40px;
			min-height: 0;
			flex: 0 0 auto;
			border-radius: var(--radius-base);
		}

		&__bone-line {
			width: 70%;
			height: 10px;
			min-height: 0;

			&--short {
				width: 40%;
			}
		}

		&__state,
		&__empty {
			display: flex;
			flex-direction: column;
			align-items: center;
			gap: var(--space-smaller);
			padding: var(--space-large) var(--space-base) var(--space-medium);
			text-align: center;

			:global(.icon-tile) {
				margin-bottom: var(--space-smaller);
			}

			:global(.button) {
				margin-top: var(--space-small);
			}
		}

		&__empty {
			padding: var(--space-medium) var(--space-base);
			border: 1.5px dashed var(--color-border--interactive--hover);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
		}

		&__empty-icon {
			display: inline-flex;
			margin-bottom: var(--space-smaller);
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 22px;
				height: 22px;
			}
		}

		&__state-title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}

		&__state-hint {
			max-width: 260px;
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-large);
		}

		// --- Photos ---------------------------------------------------------------------------------
		&__photos {
			display: grid;
			grid-template-columns: repeat(3, minmax(0, 1fr));
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__photo {
			position: relative;
			height: 92px;
		}

		&__photo-open {
			position: relative;
			display: block;
			width: 100%;
			height: 100%;
			overflow: hidden;
			padding: 0;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
			cursor: pointer;

			:global(.file-thumb) {
				width: 100%;
				height: 100%;
				aspect-ratio: auto;
				border-radius: 0;
			}

			:global(img) {
				width: 100%;
				height: 100%;
				object-fit: cover;
			}

			&:focus-visible {
				outline: none;
			}
		}

		// Pointing at a photo, or reaching it by keyboard: the interactive ring and its two round buttons.
		&__photo:hover &__photo-open,
		&__photo:focus-within &__photo-open {
			border-color: transparent;
			box-shadow: 0 0 0 2px var(--color-interactive);
		}

		&__photo-actions {
			position: absolute;
			top: 6px;
			right: 6px;
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			opacity: 0;
			transition: opacity var(--timing-quick);
		}

		&__photo:hover &__photo-actions,
		&__photo:focus-within &__photo-actions {
			opacity: 1;
		}

		&__photo-action {
			display: grid;
			width: 28px;
			height: 28px;
			place-items: center;
			padding: 0;
			border: 0;
			border-radius: var(--radius-circle);
			color: var(--color-icon);
			background: var(--color-surface);
			box-shadow: 0 1px 3px color-mix(in srgb, var(--color-heading) 12%, transparent);
			cursor: pointer;

			:global(svg) {
				display: block;
				width: 14px;
				height: 14px;
			}

			&:hover {
				color: var(--color-heading);
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__more {
			position: absolute;
			inset: 0;
			display: grid;
			place-items: center;
			color: var(--color-white);
			background: var(--color-overlay);
			font-size: var(--typography--fontSize-larger);
			font-weight: 700;
		}

		// --- Documents ------------------------------------------------------------------------------
		&__list {
			display: flex;
			flex-direction: column;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__item {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-slim) var(--space-slim) var(--space-slim) var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__item-icon {
			display: grid;
			width: 40px;
			height: 40px;
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
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__item-meta {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__item :global([data-state='open']) {
			background: var(--color-surface--active);
		}
	}

	// A plain card (create pages, pop-ups) keeps its own padding; documents sit edge to edge inside it.
	.record-files__list .record-files__item:first-child {
		border-top: 0;
	}

	.record-files__photos + .record-files__list .record-files__item:first-child {
		margin-top: var(--space-small);
		border-top: var(--border-base) solid var(--color-border);
	}

	// Record page rail (App look): the body runs edge to edge, photos padded 16.
	:global(.rail-card--flush) {
		.record-files__notice {
			margin: var(--space-base) var(--space-base) 0;
		}

		.record-files__state,
		.record-files__empty {
			margin: var(--space-base);
		}

		.record-files__photos {
			padding: var(--space-base);
		}

		.record-files__loading .record-files__photos {
			padding-bottom: var(--space-small);
		}

		.record-files__list .record-files__item:first-child,
		.record-files__photos + .record-files__list .record-files__item:first-child {
			margin-top: 0;
			border-top: var(--border-base) solid var(--color-border);
		}
	}

	@keyframes record-files-spin {
		to {
			transform: rotate(360deg);
		}
	}

	@media (hover: none) {
		.record-files__photo-actions {
			opacity: 1;
		}
	}
</style>
