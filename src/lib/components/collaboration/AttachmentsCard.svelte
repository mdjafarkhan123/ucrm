<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { onDestroy, untrack } from 'svelte';
	import AttachmentSurface from '$lib/components/collaboration/AttachmentSurface.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import Lightbox, { type LightboxItem } from '$lib/components/ui/Lightbox.svelte';
	import AuthorMeta from '$lib/components/collaboration/AuthorMeta.svelte';
	import { formatFileSize } from '$lib/collaboration/format';
	import { iconForMimeType } from '$lib/collaboration/file-icons';
	import { createImageThumbnail } from '$lib/collaboration/image-thumbnail';
	import {
		ALLOWED_ATTACHMENT_MIME_TYPES,
		MAX_ATTACHMENT_SIZE_BYTES
	} from '$lib/collaboration/attachment-limits';
	import {
		activityKey,
		attachmentImageUrl,
		attachmentsKey,
		createAttachment,
		deleteAttachment,
		fetchAttachmentDownloadUrl,
		fetchAttachments,
		fetchProfiles,
		isImageAttachment,
		presignAttachmentUpload,
		profilesKey,
		uploadAttachmentFile,
		type Attachment,
		type EntityType
	} from '$lib/collaboration/api';
	import uploadIcon from '@tabler/icons/outline/upload.svg?raw';
	import paperclipIcon from '@tabler/icons/outline/paperclip.svg?raw';
	import downloadIcon from '@tabler/icons/outline/download.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';
	import photoIcon from '@tabler/icons/outline/photo.svg?raw';

	// Files for one record. Nothing here reaches the server on its own: picking a file queues it, deleting
	// one marks it to go, and the page's Save does the lot through `saveAll()`. The house rule is that no
	// write happens without the user pressing a button that saves; this card sits in the page body, so that
	// button is the page's. It is why the card behaves the same on a create form, where the record does not
	// exist yet, as on a detail page where it does.
	//
	// Photos show as previews rather than file icons, and clicking one opens the lightbox.
	let {
		entityType,
		entityId,
		canManage = true,
		currentUserId,
		title = 'Attachments',
		surface = 'rail',
		kind = 'all',
		includeIds,
		onPendingChange
	}: {
		entityType: EntityType;
		entityId?: string;
		canManage?: boolean;
		currentUserId?: string;
		title?: string;
		surface?: 'rail' | 'section';
		kind?: 'all' | 'documents' | 'images';
		/** When supplied, only these already-saved files belong to this surface. Queued files still show. */
		includeIds?: string[];
		/** Reports how many changes are waiting, so the page can count them as unsaved and light its bar. */
		onPendingChange?: (count: number) => void;
	} = $props();

	const queryClient = useQueryClient();
	const uid = $props.id();
	const pickerId = `${uid}-picker`;

	// The id everything saves against: the record's own once it has one, otherwise the id handed to
	// saveAll by the page that just created it.
	let createdEntityId = $state('');
	const targetId = $derived(entityId ?? createdEntityId);

	const attachmentsQuery = createQuery<Attachment[]>(() => ({
		queryKey: attachmentsKey(entityType, targetId),
		queryFn: () => fetchAttachments(entityType, targetId),
		enabled: Boolean(targetId)
	}));
	const saved = $derived.by(() => {
		if (!targetId) return [];
		const included = includeIds ? new Set(includeIds) : null;
		return (attachmentsQuery.data ?? []).filter((file) => {
			if (included && !included.has(file.id)) return false;
			if (kind === 'images') return isImageAttachment(file);
			if (kind === 'documents') return !isImageAttachment(file);
			return true;
		});
	});
	const accept = $derived(kind === 'images' ? 'image/*' : undefined);
	const surfaceIcon = $derived(kind === 'images' ? photoIcon : paperclipIcon);

	const uploaderIds = $derived([
		...new Set(saved.map((file) => file.uploaded_by).filter((id): id is string => Boolean(id)))
	]);
	const profilesQuery = createQuery(() => ({
		queryKey: profilesKey(uploaderIds),
		queryFn: () => fetchProfiles(uploaderIds),
		enabled: uploaderIds.length > 0
	}));
	const profileById = $derived(
		new Map((profilesQuery.data ?? []).map((profile) => [profile.id, profile]))
	);

	// --- What is waiting to be saved --------------------------------------------------------------------

	type QueuedFile = {
		key: string;
		file: File;
		/** The small copy for the grid, made in the browser at pick time. Null when it could not be made. */
		thumbnail: Blob | null;
		/** Local preview of the picked file, so a photo shows before it has been anywhere near the server. */
		previewUrl: string;
		status: 'queued' | 'uploading' | 'error';
		progress: number;
		error: string;
		retryable: boolean;
	};

	let queue = $state<QueuedFile[]>([]);
	let removedIds = $state<string[]>([]);
	let storageUnavailable = $state(false);
	let downloadError = $state('');
	let fileInputEl: HTMLInputElement | undefined = $state();

	const keptSaved = $derived(saved.filter((file) => !removedIds.includes(file.id)));
	const total = $derived(keptSaved.length + queue.length);
	const pendingCount = $derived(queue.length + removedIds.length);

	// Reports the count and nothing else. The callback writes state on the page that owns this card, so it
	// runs untracked — otherwise the page's own reaction would come back round as a dependency here.
	$effect(() => {
		const count = pendingCount;
		untrack(() => onPendingChange?.(count));
	});

	// Queue items live inside a `$state` array, so they are only reactive when reached through it. Patching
	// by key rather than holding a reference is what keeps a progress bar actually moving.
	function patchQueued(key: string, changes: Partial<QueuedFile>) {
		queue = queue.map((item) => (item.key === key ? { ...item, ...changes } : item));
	}

	function refresh(id: string) {
		void queryClient.invalidateQueries({ queryKey: attachmentsKey(entityType, id) });
		void queryClient.invalidateQueries({ queryKey: activityKey(entityType, id) });
	}

	function addFiles(fileList: FileList | null) {
		if (!fileList) return;
		for (const file of Array.from(fileList)) {
			if (kind === 'images' && !file.type.startsWith('image/')) continue;
			if (kind === 'documents' && file.type.startsWith('image/')) continue;
			const tooBig = file.size > MAX_ATTACHMENT_SIZE_BYTES;
			const wrongType = !(ALLOWED_ATTACHMENT_MIME_TYPES as readonly string[]).includes(file.type);
			const key = `${file.name}-${file.size}-${Date.now()}-${Math.random()}`;
			queue.push({
				key,
				file,
				thumbnail: null,
				previewUrl: '',
				status: tooBig || wrongType ? 'error' : 'queued',
				progress: 0,
				error: tooBig
					? 'This file is over 25 MB.'
					: wrongType
						? 'That file type is not supported.'
						: '',
				// A file the office has to swap out rather than try again.
				retryable: !tooBig && !wrongType
			});

			// Shrinking now means one decode covers both the preview on screen and the copy that gets
			// uploaded. A format the browser cannot read falls back to previewing the original.
			if (!tooBig && !wrongType && file.type.startsWith('image/')) {
				void createImageThumbnail(file).then((thumbnail) => {
					patchQueued(key, {
						thumbnail,
						previewUrl: URL.createObjectURL(thumbnail ?? file)
					});
				});
			}
		}
		if (fileInputEl) fileInputEl.value = '';
	}

	function releasePreview(item: QueuedFile) {
		if (item.previewUrl) URL.revokeObjectURL(item.previewUrl);
	}

	function dropFromQueue(key: string) {
		const item = queue.find((entry) => entry.key === key);
		if (item) releasePreview(item);
		queue = queue.filter((entry) => entry.key !== key);
	}

	function stageRemove(attachment: Attachment) {
		if (!removedIds.includes(attachment.id)) removedIds = [...removedIds, attachment.id];
	}

	function undoRemove(attachment: Attachment) {
		removedIds = removedIds.filter((id) => id !== attachment.id);
	}

	onDestroy(() => {
		for (const item of queue) releasePreview(item);
	});

	// --- Saving -----------------------------------------------------------------------------------------

	// Every step happens per file, so one failure never touches the others and never suggests the record
	// itself failed to save. A file leaves the queue the moment it lands, which is what keeps a retry from
	// creating the same attachment twice.
	async function uploadOne(item: QueuedFile, id: string) {
		if (!item.retryable) return;
		patchQueued(item.key, { status: 'uploading', progress: 0, error: '' });

		try {
			const presigned = await presignAttachmentUpload({
				entityType,
				entityId: id,
				fileName: item.file.name,
				mimeType: item.file.type,
				sizeBytes: item.file.size
			});
			// Only when the bar would actually move. Each patch rebuilds the queue array and everything
			// derived from it, and the browser reports progress far more often than a percentage changes.
			let shownPercent = -1;
			await uploadAttachmentFile(presigned.upload_url, item.file, (fraction) => {
				const percent = Math.round(fraction * 100);
				if (percent === shownPercent) return;
				shownPercent = percent;
				patchQueued(item.key, { progress: fraction });
			});

			// The preview is a convenience, not the file. If it fails to upload the attachment still saves
			// and simply falls back to showing the original.
			let thumbnailObjectKey: string | null = null;
			if (item.thumbnail && presigned.thumbnail_upload_url && presigned.thumbnail_object_key) {
				try {
					await uploadAttachmentFile(presigned.thumbnail_upload_url, item.thumbnail);
					thumbnailObjectKey = presigned.thumbnail_object_key;
				} catch (thumbnailError) {
					console.error('Could not upload the preview for a photo.', thumbnailError);
				}
			}

			await createAttachment({
				entityType,
				entityId: id,
				fileName: item.file.name,
				mimeType: item.file.type,
				sizeBytes: item.file.size,
				objectKey: presigned.object_key,
				thumbnailObjectKey
			});
			dropFromQueue(item.key);
		} catch (error) {
			const message = error instanceof Error ? error.message : 'That file could not be uploaded.';
			if (message.includes('storage is not configured')) storageUnavailable = true;
			patchQueued(item.key, { status: 'error', error: message });
		}
	}

	/** Writes everything staged here: uploads the picked files, then removes the ones marked to go. Returns
	 *  how many failed, so the page can decide whether to move on or keep the office here to retry. */
	export async function saveAll(id: string) {
		createdEntityId = id;

		const waiting = queue.filter((item) => item.retryable);
		if (waiting.length > 0) await Promise.all(waiting.map((item) => uploadOne(item, id)));

		let failures = queue.filter((item) => item.status === 'error').length;

		// One at a time, dropped from the list as each lands, so a failure halfway leaves only the files
		// that still need removing behind.
		for (const attachmentId of [...removedIds]) {
			try {
				await deleteAttachment(attachmentId);
				removedIds = removedIds.filter((entry) => entry !== attachmentId);
			} catch (error) {
				console.error('Could not delete an attachment.', attachmentId, error);
				failures += 1;
			}
		}

		refresh(id);
		return failures;
	}

	/** Throws away everything staged, for a page whose Cancel discards its whole draft. */
	export function discardChanges() {
		for (const item of queue) releasePreview(item);
		queue = [];
		removedIds = [];
	}

	async function retry(item: QueuedFile) {
		if (!targetId) return;
		await uploadOne(item, targetId);
	}

	async function download(attachment: Attachment) {
		downloadError = '';
		try {
			const url = await fetchAttachmentDownloadUrl(attachment.id);
			window.open(url, '_blank', 'noopener,noreferrer');
		} catch (error) {
			downloadError = error instanceof Error ? error.message : 'That file could not be downloaded.';
			if (downloadError.includes('storage is not configured')) storageUnavailable = true;
		}
	}

	// --- Photos and documents ---------------------------------------------------------------------------
	// Photos get a grid of previews; anything with nothing to preview keeps the plain list row underneath.

	type PhotoTile = {
		key: string;
		caption: string;
		thumbSrc: string;
		fullSrc: string;
		/** Marked to be deleted on save. Stays on screen, dimmed, with an Undo. */
		removed: boolean;
		/** Picked but not uploaded yet, so it is drawn from a local preview. */
		queued: boolean;
		attachment?: Attachment;
		queuedItem?: QueuedFile;
	};

	// A photo that went wrong — too big, unsupported, or an upload that failed — leaves the grid and joins
	// the list below, where there is room to say what happened and offer a Retry. A blank tile explains
	// nothing.
	const isQueuedImage = (item: QueuedFile) =>
		item.file.type.startsWith('image/') && item.status !== 'error';

	const photoTiles = $derived<PhotoTile[]>([
		...queue.filter(isQueuedImage).map((item) => ({
			key: item.key,
			caption: item.file.name,
			thumbSrc: item.previewUrl,
			fullSrc: item.previewUrl,
			removed: false,
			queued: true,
			queuedItem: item
		})),
		...saved.filter(isImageAttachment).map((attachment) => ({
			key: attachment.id,
			caption: attachment.file_name,
			thumbSrc: attachmentImageUrl(attachment.id, 'thumb'),
			fullSrc: attachmentImageUrl(attachment.id),
			removed: removedIds.includes(attachment.id),
			queued: false,
			attachment
		}))
	]);

	const documentQueue = $derived(queue.filter((item) => !isQueuedImage(item)));
	const documentSaved = $derived(saved.filter((file) => !isImageAttachment(file)));
	const hasDocuments = $derived(documentQueue.length + documentSaved.length > 0);

	// A photo on its way out is not part of the gallery — its only action is Undo.
	const galleryTiles = $derived(photoTiles.filter((tile) => !tile.removed));
	const lightboxItems = $derived<LightboxItem[]>(
		galleryTiles.map((tile) => ({
			id: tile.key,
			src: tile.fullSrc,
			thumbSrc: tile.thumbSrc,
			caption: tile.caption
		}))
	);

	let lightboxOpen = $state(false);
	let lightboxIndex = $state(0);

	function openLightbox(tile: PhotoTile) {
		const position = galleryTiles.findIndex((entry) => entry.key === tile.key);
		if (position === -1) return;
		lightboxIndex = position;
		lightboxOpen = true;
	}

	// Only a file that exists on the server can be downloaded; a queued one is still on this machine.
	function downloadFromLightbox(item: LightboxItem) {
		const tile = galleryTiles.find((entry) => entry.key === item.id);
		if (tile?.attachment) void download(tile.attachment);
	}

	const canDownloadCurrentPhoto = $derived(
		Boolean(galleryTiles[lightboxIndex] && !galleryTiles[lightboxIndex].queued)
	);

	function menuFor(attachment: Attachment) {
		return [
			{ label: 'Download', icon: downloadIcon, onSelect: () => download(attachment) },
			...(canManage
				? [
						{
							label: 'Delete',
							icon: trashIcon,
							destructive: true,
							onSelect: () => stageRemove(attachment)
						}
					]
				: [])
		];
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<AttachmentSurface {surface} {title} icon={surfaceIcon} count={total}>
	{#snippet actions()}
		{#if canManage}
			<input
				bind:this={fileInputEl}
				type="file"
				multiple
				{accept}
				class="attachments-card__file-input"
				id={pickerId}
				onchange={(event) => addFiles((event.currentTarget as HTMLInputElement).files)}
			/>
			<Button size="small" variant="secondary" onclick={() => fileInputEl?.click()}>
				<span class="attachments-card__button-icon" aria-hidden="true">{@html uploadIcon}</span>Add
			</Button>
		{/if}
	{/snippet}

	{#if storageUnavailable}
		<p class="attachments-card__notice" role="alert">
			File storage isn't set up yet. Ask an admin to connect Cloudflare R2.
		</p>
	{/if}
	{#if downloadError}
		<p class="attachments-card__notice" role="alert">{downloadError}</p>
	{/if}

	{#if total === 0 && photoTiles.length === 0}
		{#if targetId && attachmentsQuery.isPending}
			<p class="attachments-card__muted">Loading files…</p>
		{:else if targetId && attachmentsQuery.isError}
			<p class="attachments-card__notice" role="alert">Files could not be loaded.</p>
		{:else}
			<div class="attachments-card__empty">
				<span aria-hidden="true">{@html paperclipIcon}</span>
				<p>
					{canManage
						? 'Add photos and documents. They save with the rest of the page.'
						: 'No files yet.'}
				</p>
				{#if canManage}<span class="attachments-card__hint">Up to 25 MB per file</span>{/if}
			</div>
		{/if}
	{:else}
		{#if photoTiles.length > 0}
			<ul class="attachments-card__photos">
				{#each photoTiles as tile (tile.key)}
					<li class="attachments-card__photo" class:attachments-card__photo--removed={tile.removed}>
						{#if tile.removed && tile.attachment}
							<span class="attachments-card__photo-frame">
								<img src={tile.thumbSrc} alt="" loading="lazy" />
							</span>
							<button
								type="button"
								class="attachments-card__photo-undo"
								onclick={() => tile.attachment && undoRemove(tile.attachment)}
							>
								Undo
							</button>
						{:else}
							<button
								type="button"
								class="attachments-card__photo-open"
								aria-label={`View ${tile.caption}`}
								onclick={() => openLightbox(tile)}
							>
								{#if tile.thumbSrc}
									<img src={tile.thumbSrc} alt="" loading="lazy" />
								{:else}
									<span class="attachments-card__photo-loading" aria-hidden="true"></span>
								{/if}
							</button>

							{#if tile.queued}
								<span class="attachments-card__photo-badge">
									{tile.queuedItem?.status === 'uploading' ? 'Saving…' : 'Not saved'}
								</span>
							{/if}

							{#if canManage}
								<button
									type="button"
									class="attachments-card__photo-remove"
									aria-label={`Remove ${tile.caption}`}
									onclick={() => {
										if (tile.attachment) stageRemove(tile.attachment);
										else if (tile.queuedItem) dropFromQueue(tile.queuedItem.key);
									}}
								>
									{@html xIcon}
								</button>
							{/if}
						{/if}
					</li>
				{/each}
			</ul>
		{/if}

		{#if hasDocuments}
			<ul class="attachments-card__list">
				{#each documentQueue as item (item.key)}
					<li
						class="attachments-card__item"
						class:attachments-card__item--error={item.status === 'error'}
					>
						<span class="attachments-card__item-icon" aria-hidden="true">
							{@html iconForMimeType(item.file.type)}
						</span>
						<div class="attachments-card__item-body">
							<span class="attachments-card__item-name">{item.file.name}</span>
							{#if item.status === 'error'}
								<span class="attachments-card__item-error">{item.error}</span>
							{:else if item.status === 'uploading'}
								<span class="attachments-card__progress">
									<span
										class="attachments-card__progress-bar"
										style={`width: ${Math.round(item.progress * 100)}%`}
									></span>
								</span>
							{:else}
								<span class="attachments-card__item-meta">
									{formatFileSize(item.file.size)} · Waiting for save
								</span>
							{/if}
						</div>

						{#if item.status === 'error' && item.retryable && targetId}
							<button type="button" class="attachments-card__action" onclick={() => retry(item)}>
								Retry
							</button>
						{/if}
						{#if item.status !== 'uploading'}
							<button
								type="button"
								class="attachments-card__remove"
								aria-label={`Remove ${item.file.name}`}
								onclick={() => dropFromQueue(item.key)}
							>
								{@html xIcon}
							</button>
						{/if}
					</li>
				{/each}

				{#each documentSaved as attachment (attachment.id)}
					{@const removed = removedIds.includes(attachment.id)}
					<li class="attachments-card__item" class:attachments-card__item--removed={removed}>
						<span class="attachments-card__item-icon" aria-hidden="true">
							{@html iconForMimeType(attachment.mime_type)}
						</span>
						<div class="attachments-card__item-body">
							<span class="attachments-card__item-name">{attachment.file_name}</span>
							<span class="attachments-card__item-meta">
								{#if removed}
									Removed when you save
								{:else}
									{formatFileSize(attachment.size_bytes)} ·
									<AuthorMeta
										userId={attachment.uploaded_by}
										profile={attachment.uploaded_by
											? profileById.get(attachment.uploaded_by)
											: undefined}
										{currentUserId}
										timestamp={attachment.created_at}
									/>
								{/if}
							</span>
						</div>
						{#if removed}
							<button
								type="button"
								class="attachments-card__action"
								onclick={() => undoRemove(attachment)}
							>
								Undo
							</button>
						{:else}
							<DropdownMenu triggerLabel="File actions" items={menuFor(attachment)} />
						{/if}
					</li>
				{/each}
			</ul>
		{/if}
	{/if}
</AttachmentSurface>

<Lightbox
	open={lightboxOpen}
	items={lightboxItems}
	bind:index={lightboxIndex}
	onClose={() => (lightboxOpen = false)}
	onDownload={canDownloadCurrentPhoto ? downloadFromLightbox : undefined}
/>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.attachments-card {
		&__file-input {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip: rect(0 0 0 0);
			white-space: nowrap;
		}

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

		&__hint {
			font-size: var(--typography--fontSize-smaller);
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

			&--removed {
				opacity: 0.45;
			}
		}

		&__photo-open,
		&__photo-frame {
			display: block;
			width: 100%;
			height: 100%;
			overflow: hidden;
			padding: 0;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__photo-open {
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

		&__photo-open img,
		&__photo-frame img {
			display: block;
			width: 100%;
			height: 100%;
			object-fit: cover;
		}

		// Holds the tile's shape while the browser is still shrinking the picked photo.
		&__photo-loading {
			display: block;
			width: 100%;
			height: 100%;
			background: var(--color-surface--hover);
		}

		&__photo-badge {
			position: absolute;
			right: var(--space-smaller);
			bottom: var(--space-smaller);
			left: var(--space-smaller);
			overflow: hidden;
			padding: 2px 4px;
			border-radius: var(--radius-small);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
			font-size: var(--typography--fontSize-smaller);
			text-align: center;
			text-overflow: ellipsis;
			white-space: nowrap;
			pointer-events: none;
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

		&__photo-undo {
			position: absolute;
			inset: 0;
			border: 0;
			border-radius: var(--radius-base);
			color: var(--color-interactive);
			background: rgba(255, 255, 255, 0.72);
			font: inherit;
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			cursor: pointer;

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
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

			&--error {
				border-color: var(--color-critical);
			}

			&--removed {
				opacity: 0.6;

				.attachments-card__item-name {
					text-decoration: line-through;
				}
			}
		}

		&__item-icon {
			display: grid;
			width: 32px;
			height: 32px;
			flex: 0 0 auto;
			place-items: center;
			border-radius: var(--radius-base);
			color: var(--color-icon);
			background: var(--color-surface--background);

			:global(svg) {
				display: block;
				width: 20px;
				height: 20px;
			}
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
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}

		&__item-error {
			color: var(--color-critical);
			font-size: var(--typography--fontSize-smaller);
		}

		&__progress {
			display: block;
			height: 6px;
			overflow: hidden;
			border-radius: var(--radius-large);
			background: var(--color-surface--background);
		}

		&__progress-bar {
			display: block;
			height: 100%;
			background: var(--color-interactive);
			transition: width var(--timing-base) ease-out;
		}

		&__action {
			flex: 0 0 auto;
			border: 0;
			color: var(--color-interactive);
			background: transparent;
			font: inherit;
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			cursor: pointer;

			&:hover {
				text-decoration: underline;
			}
		}

		&__remove {
			display: grid;
			width: 20px;
			height: 20px;
			flex: 0 0 auto;
			place-items: center;
			border: 0;
			border-radius: var(--radius-circle);
			color: var(--color-icon--secondary);
			background: transparent;
			cursor: pointer;

			&:hover {
				color: var(--color-heading);
				background: var(--color-surface--hover);
			}

			:global(svg) {
				display: block;
				width: 14px;
				height: 14px;
			}
		}
	}

	@media (hover: none) {
		.attachments-card__photo-remove {
			opacity: 1;
		}
	}
</style>
