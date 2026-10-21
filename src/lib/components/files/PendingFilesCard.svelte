<script lang="ts">
	import { onDestroy } from 'svelte';
	import AttachmentSurface from '$lib/components/collaboration/AttachmentSurface.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import loaderIcon from '@tabler/icons/outline/loader-2.svg?raw';
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
		if (!item.retryable || item.status === 'uploading') return;
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
		const waiting = queue.filter((item) => item.retryable && item.status !== 'uploading');
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
	let retrying = $state<string[]>([]);
	async function retry(item: QueuedFile) {
		if (!lastSaveId || retrying.includes(item.key)) return;
		retrying = [...retrying, item.key];
		try {
			await uploadOne(item, lastSaveId);
		} finally {
			retrying = retrying.filter((key) => key !== item.key);
		}
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
	const saving = $derived(queue.some((item) => item.status === 'uploading'));
	const failed = $derived(queue.filter((item) => item.status === 'error').length);
	const description = $derived(
		saving
			? `Saving ${total} ${total === 1 ? 'file' : 'files'}`
			: failed
				? `${failed} did not save`
				: `${total} waiting · they save with the ${entityType.replaceAll('_', ' ')}`
	);

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
<AttachmentSurface {surface} {title} icon={paperclipIcon} {description} flush>
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

	<div class="pending-files">
		{#if total === 0}
			<div class="pending-files__empty">
				<span aria-hidden="true">{@html paperclipIcon}</span>
				<p>Add photos and documents</p>
				<span class="pending-files__hint"
					>They save with the rest of the page · up to 100 MB each</span
				>
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
								<Badge
									size="small"
									dot={false}
									status={tile.queuedItem.status === 'uploading' ? 'informative' : 'warning'}
									>{#if tile.queuedItem.status === 'uploading'}<span
											class="pending-files__spinner"
											aria-hidden="true">{@html loaderIcon}</span
										>{/if}{tile.queuedItem.status === 'uploading' ? 'Saving…' : 'Not saved'}</Badge
								>
							</span>
							<button
								type="button"
								class="pending-files__photo-remove"
								disabled={tile.queuedItem.status === 'uploading'}
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
							<span
								class="pending-files__ring"
								style:--progress={`${item.status === 'uploading' ? item.progress * 360 : 0}deg`}
								><span class="pending-files__item-icon" aria-hidden="true"
									>{@html item.status === 'error'
										? alertIcon
										: iconForMimeType(item.file.type)}</span
								></span
							>
							<div class="pending-files__item-body">
								<span class="pending-files__item-name">{item.file.name}</span>
								{#if item.status === 'error'}
									<span class="pending-files__item-error">{item.error}</span>
								{:else}
									<span class="pending-files__item-meta"
										>{item.status === 'uploading'
											? `${formatFileSize(item.file.size * item.progress)} of ${formatFileSize(item.file.size)}`
											: `${formatFileSize(item.file.size)} · waits for Save`}</span
									>
								{/if}
							</div>

							{#if item.status !== 'error'}<Badge
									size="small"
									dot={false}
									status={item.status === 'uploading' ? 'informative' : 'warning'}
									>{#if item.status === 'uploading'}<span
											class="pending-files__spinner"
											aria-hidden="true">{@html loaderIcon}</span
										>{Math.round(item.progress * 100)}%{:else}Not saved{/if}</Badge
								>{/if}
							{#if (item.status === 'error' || retrying.includes(item.key)) && item.retryable && lastSaveId}
								<Button
									variant="quiet"
									size="small"
									loading={retrying.includes(item.key)}
									onclick={() => retry(item)}>Retry</Button
								>
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
	</div>
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
		:global(.badge) {
			white-space: nowrap;
			flex-shrink: 0;
		}
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
			p {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-label);
				font-weight: 600;
			}
			display: flex;
			flex-direction: column;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-large);
			margin: var(--space-base);
			background: var(--color-surface--background);
			border: 1.5px dashed var(--color-border--interactive--hover);
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
			font-size: var(--typography--fontSize-small);
		}

		// --- Photos ---------------------------------------------------------------------------------
		&__photos {
			display: grid;
			grid-template-columns: repeat(auto-fill, minmax(96px, 1fr));
			gap: var(--space-small);
			margin: 0;
			padding: var(--space-base);
			list-style: none;
		}

		&__photo {
			position: relative;
			height: 76px;
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
			right: 0;
			bottom: 6px;
			left: 0;
			overflow: hidden;
			padding: 0;
			border-radius: var(--radius-small);
			color: var(--color-warning--onSurface);
			background: transparent;
			font-size: var(--typography--fontSize-small);
			text-align: center;
			text-overflow: ellipsis;
			white-space: nowrap;
			pointer-events: none;
		}

		&__photo-remove {
			&:disabled {
				cursor: default;
				color: var(--color-disabled);
				background: var(--color-disabled--secondary);
			}
			position: absolute;
			top: 6px;
			right: 6px;
			display: grid;
			width: 24px;
			height: 24px;
			place-items: center;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			color: var(--color-icon--secondary);
			background: var(--color-surface);
			cursor: pointer;
			opacity: 1;
			transition: opacity var(--timing-quick);

			:global(svg) {
				display: block;
				width: 14px;
				height: 14px;
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
			gap: 0;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__item {
			display: flex;
			align-items: center;
			padding: var(--space-slim) var(--space-base) var(--space-slim) var(--space-medium);
			border-top: var(--border-base) solid var(--color-border);
			gap: 14px;

			&--error {
				border: var(--border-base) solid var(--color-critical);
				border-radius: var(--radius-base);
				margin: var(--space-base);
				padding: 6px;
				.pending-files__ring {
					width: 40px;
					height: 40px;
					background: var(--color-critical--surface);
					border-radius: var(--radius-base);
				}
				.pending-files__item-icon {
					color: var(--color-critical);
					background: transparent;
				}
			}
		}

		&__item-icon {
			display: grid;
			width: 35px;
			height: 35px;
			flex: 0 0 auto;
			place-items: center;
			border-radius: var(--radius-circle);
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
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__item-meta {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__item-error {
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__ring {
			display: grid;
			flex: 0 0 auto;
			width: 44px;
			height: 44px;
			place-items: center;
			border-radius: var(--radius-circle);
			background: conic-gradient(
				var(--color-interactive) var(--progress),
				var(--color-surface--background) 0
			);
		}
		&__spinner {
			display: inline-flex;
			vertical-align: middle;
			margin-right: var(--space-smaller);
			animation: pending-spin 1s linear infinite;
			:global(svg) {
				width: 12px;
				height: 12px;
			}
		}

		&__remove {
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
			display: grid;
			width: 24px;
			height: 24px;
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

	@keyframes pending-spin {
		to {
			transform: rotate(360deg);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.pending-files__spinner {
			animation: none;
		}
	}
	@media (hover: none) {
		.pending-files__photo-remove {
			opacity: 1;
		}
	}
</style>
