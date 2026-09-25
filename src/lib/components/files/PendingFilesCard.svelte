<script lang="ts">
	import { onDestroy } from 'svelte';
	import AttachmentSurface from '$lib/components/collaboration/AttachmentSurface.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Lightbox, { type LightboxItem } from '$lib/components/ui/Lightbox.svelte';
	import { createImageThumbnail } from '$lib/collaboration/image-thumbnail';
	import { iconForMimeType } from '$lib/collaboration/file-icons';
	import { uploadAttachmentFile } from '$lib/collaboration/api';
	import { MAX_FILE_SIZE_BYTES, allowedTypeFor, FILE_PICKER_ACCEPT } from '$lib/files/allowlist';
	import {
		finishFileUpload,
		formatFileSize,
		startFileUpload,
		type FileEntityType
	} from '$lib/files/api';
	import uploadIcon from '@tabler/icons/outline/upload.svg?raw';
	import paperclipIcon from '@tabler/icons/outline/paperclip.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	// Files for a record that does not exist yet -- the create forms for Client, Request and Job expense.
	// The File Manager only knows how to check and file a File that already names a real record (the safety
	// check joins it to that record the moment it publishes), so a file picked here cannot become a File
	// until the page's own Save has created that record and handed back its id. Until then this is pure
	// browser state: nothing is uploaded, nothing is reserved, exactly the house rule that nothing writes
	// without the user pressing a button that saves.
	//
	// This is why it is its own component rather than a mode of RecordFilesCard: RecordFilesCard's every
	// action (attach, remove) writes immediately because it always has a real id to write against. This one
	// never does until `saveAll` is called, so it stages instead.
	let {
		entityType,
		title = 'Attachments',
		surface = 'rail',
		onPendingChange
	}: {
		entityType: FileEntityType;
		title?: string;
		surface?: 'rail' | 'section';
		/** Reports how many files are waiting, so the page can count them as unsaved and light its bar. */
		onPendingChange?: (count: number) => void;
	} = $props();

	const uid = $props.id();
	const pickerId = `${uid}-picker`;

	type QueuedFile = {
		key: string;
		file: File;
		/** The small copy for the grid, made in the browser at pick time. Null when it could not be made. */
		thumbnail: Blob | null;
		previewUrl: string;
		status: 'queued' | 'uploading' | 'error';
		progress: number;
		error: string;
		retryable: boolean;
	};

	let queue = $state<QueuedFile[]>([]);
	let fileInputEl: HTMLInputElement | undefined = $state();

	$effect(() => {
		const count = queue.length;
		onPendingChange?.(count);
	});

	function patchQueued(key: string, changes: Partial<QueuedFile>) {
		queue = queue.map((item) => (item.key === key ? { ...item, ...changes } : item));
	}

	function addFiles(fileList: FileList | null) {
		if (!fileList) return;
		for (const file of Array.from(fileList)) {
			const allowed = allowedTypeFor(file.name);
			const tooBig = file.size > MAX_FILE_SIZE_BYTES;
			const key = `${file.name}-${file.size}-${Date.now()}-${Math.random()}`;
			queue.push({
				key,
				file,
				thumbnail: null,
				previewUrl: '',
				status: tooBig || !allowed ? 'error' : 'queued',
				progress: 0,
				error: tooBig
					? 'Files can be up to 100 MB.'
					: !allowed
						? 'That kind of file cannot be added.'
						: '',
				retryable: !tooBig && Boolean(allowed)
			});

			if (!tooBig && allowed && file.type.startsWith('image/')) {
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

	onDestroy(() => {
		for (const item of queue) releasePreview(item);
	});

	// --- Saving -----------------------------------------------------------------------------------------

	// One file at a time reaching the server, so a failure never touches the others. A file leaves the queue
	// the moment it lands, which is what keeps a retry from creating the same File twice.
	async function uploadOne(item: QueuedFile, id: string) {
		if (!item.retryable) return;
		patchQueued(item.key, { status: 'uploading', progress: 0, error: '' });

		try {
			const started = await startFileUpload(item.file, { originType: entityType, originId: id });
			let shownPercent = -1;
			await uploadAttachmentFile(started.upload_url, item.file, (fraction) => {
				const percent = Math.round(fraction * 100);
				if (percent === shownPercent) return;
				shownPercent = percent;
				patchQueued(item.key, { progress: fraction });
			});
			await finishFileUpload(started.file.id);
			dropFromQueue(item.key);
		} catch (error) {
			const message = error instanceof Error ? error.message : 'That file could not be uploaded.';
			patchQueued(item.key, { status: 'error', error: message });
		}
	}

	// The id everything saves against. Set the moment saveAll is called, and reused by a retry afterwards --
	// nothing removes a file from the queue except landing or being dropped, so the same id still applies.
	let lastSaveId = $state('');

	/** Uploads every file staged here against the record's now-real id. Returns how many failed, so the
	 *  page can decide whether to move on or keep the office here to retry. */
	export async function saveAll(id: string) {
		lastSaveId = id;
		const waiting = queue.filter((item) => item.retryable);
		if (waiting.length > 0) await Promise.all(waiting.map((item) => uploadOne(item, id)));
		return queue.filter((item) => item.status === 'error').length;
	}

	/** Throws away everything staged, for a page whose Cancel discards its whole draft. */
	export function discardChanges() {
		for (const item of queue) releasePreview(item);
		queue = [];
	}

	// The page's Save already reported the failure, so a successful retry needs its own visible change; a
	// failed retry keeps its inline error on the row.
	async function retry(item: QueuedFile) {
		if (!lastSaveId) return;
		await uploadOne(item, lastSaveId);
	}

	// --- Photos and documents ---------------------------------------------------------------------------

	type PhotoTile = {
		key: string;
		caption: string;
		thumbSrc: string;
		queuedItem: QueuedFile;
	};

	const isQueuedImage = (item: QueuedFile) =>
		item.file.type.startsWith('image/') && item.status !== 'error';

	const photoTiles = $derived<PhotoTile[]>(
		queue.filter(isQueuedImage).map((item) => ({
			key: item.key,
			caption: item.file.name,
			thumbSrc: item.previewUrl,
			queuedItem: item
		}))
	);

	const documentQueue = $derived(queue.filter((item) => !isQueuedImage(item)));
	const total = $derived(queue.length);

	const lightboxItems = $derived<LightboxItem[]>(
		photoTiles.map((tile) => ({
			id: tile.key,
			src: tile.thumbSrc,
			thumbSrc: tile.thumbSrc,
			caption: tile.caption
		}))
	);
	let lightboxOpen = $state(false);
	let lightboxIndex = $state(0);

	function openLightbox(tile: PhotoTile) {
		const position = photoTiles.findIndex((entry) => entry.key === tile.key);
		if (position === -1) return;
		lightboxIndex = position;
		lightboxOpen = true;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<AttachmentSurface {surface} {title} icon={paperclipIcon} count={total}>
	{#snippet actions()}
		<input
			bind:this={fileInputEl}
			type="file"
			multiple
			accept={FILE_PICKER_ACCEPT}
			class="pending-files__file-input"
			id={pickerId}
			aria-label="Upload files"
			onchange={(event) => addFiles((event.currentTarget as HTMLInputElement).files)}
		/>
		<Button size="small" variant="secondary" onclick={() => fileInputEl?.click()}>
			<span class="pending-files__button-icon" aria-hidden="true">{@html uploadIcon}</span>Add
		</Button>
	{/snippet}

	{#if total === 0}
		<div class="pending-files__empty">
			<span aria-hidden="true">{@html paperclipIcon}</span>
			<p>Add photos and documents. They save with the rest of the page.</p>
			<span class="pending-files__hint">Up to 100 MB per file</span>
		</div>
	{:else}
		{#if photoTiles.length > 0}
			<ul class="pending-files__photos">
				{#each photoTiles as tile (tile.key)}
					<li class="pending-files__photo">
						<button
							type="button"
							class="pending-files__photo-open"
							aria-label={`View ${tile.caption}`}
							onclick={() => openLightbox(tile)}
						>
							{#if tile.thumbSrc}
								<img src={tile.thumbSrc} alt="" loading="lazy" />
							{:else}
								<span class="pending-files__photo-loading" aria-hidden="true"></span>
							{/if}
						</button>
						<span class="pending-files__photo-badge">
							{tile.queuedItem.status === 'uploading' ? 'Saving…' : 'Not saved'}
						</span>
						<button
							type="button"
							class="pending-files__photo-remove"
							aria-label={`Remove ${tile.caption}`}
							onclick={() => dropFromQueue(tile.queuedItem.key)}
						>
							{@html xIcon}
						</button>
					</li>
				{/each}
			</ul>
		{/if}

		{#if documentQueue.length > 0}
			<ul class="pending-files__list">
				{#each documentQueue as item (item.key)}
					<li
						class="pending-files__item"
						class:pending-files__item--error={item.status === 'error'}
					>
						<span class="pending-files__item-icon" aria-hidden="true">
							{@html iconForMimeType(item.file.type)}
						</span>
						<div class="pending-files__item-body">
							<span class="pending-files__item-name">{item.file.name}</span>
							{#if item.status === 'error'}
								<span class="pending-files__item-error">{item.error}</span>
							{:else if item.status === 'uploading'}
								<span class="pending-files__progress">
									<span
										class="pending-files__progress-bar"
										style={`width: ${Math.round(item.progress * 100)}%`}
									></span>
								</span>
							{:else}
								<span class="pending-files__item-meta">
									{formatFileSize(item.file.size)} · Waiting for save
								</span>
							{/if}
						</div>

						{#if item.status === 'error' && item.retryable && lastSaveId}
							<button type="button" class="pending-files__action" onclick={() => retry(item)}>
								Retry
							</button>
						{/if}
						{#if item.status !== 'uploading'}
							<button
								type="button"
								class="pending-files__remove"
								aria-label={`Remove ${item.file.name}`}
								onclick={() => dropFromQueue(item.key)}
							>
								{@html xIcon}
							</button>
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
/>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.pending-files {
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

		&__photo-open img {
			display: block;
			width: 100%;
			height: 100%;
			object-fit: cover;
		}

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

			&--error {
				border-color: var(--color-critical);
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
		.pending-files__photo-remove {
			opacity: 1;
		}
	}
</style>
