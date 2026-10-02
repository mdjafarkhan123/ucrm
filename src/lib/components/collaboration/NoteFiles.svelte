<script lang="ts">
	import Lightbox, { type LightboxItem } from '$lib/components/ui/Lightbox.svelte';
	import FileThumb from '$lib/components/files/FileThumb.svelte';
	import { formatFileSize, type FileKind, type FileProcessingState } from '$lib/files/api';
	import type { NoteFile } from '$lib/collaboration/api';
	import downloadIcon from '@tabler/icons/outline/download.svg?raw';

	// The photos and files a Note carries, under its text. Photos show as small tiles that open the
	// Lightbox; anything else is a row with its name, size and a download button. A file still being checked
	// shows as such and cannot be opened yet. The caller says where pictures and downloads come from: the
	// Brief goes through the card, a record page through the File Manager's own routes.
	let {
		files,
		imageSrc,
		onDownload
	}: {
		files: NoteFile[];
		imageSrc: (file: NoteFile, size: 'thumb' | 'full') => string;
		onDownload: (file: NoteFile) => void;
	} = $props();

	const photos = $derived(files.filter((file) => file.kind === 'image'));
	const others = $derived(files.filter((file) => file.kind !== 'image'));
	const viewable = $derived(photos.filter((file) => file.processing_state === 'available'));

	let lightboxOpen = $state(false);
	let lightboxIndex = $state(0);

	const lightboxItems = $derived<LightboxItem[]>(
		viewable.map((file) => ({
			id: file.id,
			src: imageSrc(file, 'full'),
			thumbSrc: imageSrc(file, 'thumb'),
			caption: file.display_name
		}))
	);

	function openPhoto(file: NoteFile) {
		const position = viewable.findIndex((entry) => entry.id === file.id);
		if (position === -1) return;
		lightboxIndex = position;
		lightboxOpen = true;
	}

	function downloadFromLightbox(item: LightboxItem) {
		const file = viewable.find((entry) => entry.id === item.id);
		if (file) onDownload(file);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if files.length > 0}
	<div class="note-files">
		{#if photos.length > 0}
			<ul class="note-files__photos" aria-label="Photos">
				{#each photos as file (file.id)}
					{@const ready = file.processing_state === 'available'}
					<li>
						<button
							type="button"
							class="note-files__photo"
							disabled={!ready}
							aria-label={ready
								? `Open ${file.display_name}`
								: `${file.display_name} is still being checked`}
							onclick={() => openPhoto(file)}
						>
							<FileThumb
								fileId={file.id}
								displayName={file.display_name}
								mimeType={file.mime_type}
								kind={file.kind as FileKind}
								processingState={file.processing_state as FileProcessingState}
								hasThumbnail={file.has_thumbnail}
								signedSrc={ready ? imageSrc(file, 'thumb') : null}
							/>
						</button>
					</li>
				{/each}
			</ul>
		{/if}

		{#if others.length > 0}
			<ul class="note-files__documents" aria-label="Files">
				{#each others as file (file.id)}
					{@const ready = file.processing_state === 'available'}
					<li class="note-files__document">
						<FileThumb
							fileId={file.id}
							displayName={file.display_name}
							mimeType={file.mime_type}
							kind={file.kind as FileKind}
							processingState={file.processing_state as FileProcessingState}
							hasThumbnail={file.has_thumbnail}
							size="row"
						/>
						<span class="note-files__document-text">
							<span class="note-files__document-name">{file.display_name}</span>
							<span class="note-files__document-meta">
								{ready ? formatFileSize(file.size_bytes) : 'Still being checked'}
							</span>
						</span>
						{#if ready}
							<button
								type="button"
								class="note-files__download"
								aria-label={`Download ${file.display_name}`}
								onclick={() => onDownload(file)}
							>
								<span aria-hidden="true">{@html downloadIcon}</span>
							</button>
						{/if}
					</li>
				{/each}
			</ul>
		{/if}
	</div>

	<Lightbox
		open={lightboxOpen}
		items={lightboxItems}
		bind:index={lightboxIndex}
		onClose={() => (lightboxOpen = false)}
		onDownload={downloadFromLightbox}
	/>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.note-files {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin-top: var(--space-small);

		&__photos {
			display: grid;
			grid-template-columns: repeat(auto-fill, minmax(72px, 1fr));
			gap: var(--space-small);
			max-width: 420px;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__photo {
			display: block;
			width: 100%;
			padding: 0;
			overflow: hidden;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: transparent;
			cursor: zoom-in;
			transition: border-color 120ms ease;

			&:hover:not(:disabled) {
				border-color: var(--color-interactive);
			}

			&:focus-visible {
				outline: transparent;
				box-shadow: var(--shadow-focus);
			}

			&:disabled {
				cursor: default;
			}

			:global(.file-thumb) {
				aspect-ratio: 1;
				border-radius: 0;
			}
		}

		&__documents {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__document {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-smaller) var(--space-small);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}

		&__document-text {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			min-width: 0;
		}

		&__document-name {
			overflow: hidden;
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__document-meta {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}

		&__download {
			display: grid;
			flex: 0 0 auto;
			width: 32px;
			height: 32px;
			place-items: center;
			padding: 0;
			border: 0;
			border-radius: var(--radius-base);
			color: var(--color-icon--secondary);
			background: transparent;
			cursor: pointer;

			&:hover {
				color: var(--color-interactive);
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: transparent;
				box-shadow: var(--shadow-focus);
			}

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}
	}
</style>
