<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Lightbox, { type LightboxItem } from '$lib/components/ui/Lightbox.svelte';
	import FileThumb from '$lib/components/files/FileThumb.svelte';
	import { formatFileSize, type FileKind, type FileProcessingState } from '$lib/files/api';
	import type { NoteFile } from '$lib/collaboration/api';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
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
		onDownload: (file: NoteFile) => void | Promise<void>;
	} = $props();

	const photos = $derived(files.filter((file) => file.kind === 'image'));
	const others = $derived(files.filter((file) => file.kind !== 'image'));
	const viewable = $derived(photos.filter((file) => file.processing_state === 'available'));

	let downloading = $state<string[]>([]);
	async function download(file: NoteFile) {
		if (downloading.includes(file.id)) return;
		downloading = [...downloading, file.id];
		try {
			await onDownload(file);
		} finally {
			downloading = downloading.filter((id) => id !== file.id);
		}
	}
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
		if (file) return download(file);
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
							class={[
								'note-files__photo',
								file.processing_state === 'pending' && 'note-files__photo--checking'
							]}
							disabled={!ready}
							aria-label={ready
								? `Open ${file.display_name}`
								: `${file.display_name} is still being checked`}
							onclick={() => openPhoto(file)}
						>
							{#if file.processing_state === 'pending'}<span
									class="note-files__checking-icon"
									aria-hidden="true">{@html clockIcon}</span
								>{:else}
								<FileThumb
									fileId={file.id}
									displayName={file.display_name}
									mimeType={file.mime_type}
									kind={file.kind as FileKind}
									processingState={file.processing_state as FileProcessingState}
									hasThumbnail={file.has_thumbnail}
									signedSrc={ready ? imageSrc(file, 'thumb') : null}
								/>
							{/if}
						</button>
					</li>
				{/each}
			</ul>
		{/if}

		{#if others.length > 0}
			<ul class="note-files__documents" aria-label="Files">
				{#each others as file (file.id)}
					{@const ready = file.processing_state === 'available'}
					<li class={['note-files__document', !ready && 'note-files__document--checking']}>
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
								{ready ? formatFileSize(file.size_bytes) : 'Being checked'}
							</span>
						</span>
						{#if ready}
							<Button
								variant="quiet"
								size="small"
								iconOnly
								label={`Download ${file.display_name}`}
								loading={downloading.includes(file.id)}
								onclick={() => download(file)}
							>
								{@html downloadIcon}
							</Button>
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

		&__photo.note-files__photo--checking {
			background: var(--color-warning--surface);
			color: var(--color-warning);
		}
		&__checking-icon {
			display: grid;
			height: 100%;
			place-items: center;
			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}
		&__photos {
			display: grid;
			grid-template-columns: repeat(auto-fill, 96px);
			gap: var(--space-small);
			max-width: 420px;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__photo {
			display: block;
			width: 96px;
			height: 72px;
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
				aspect-ratio: auto;
				height: 100%;
				border-radius: 0;
			}
		}

		&__documents {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__document {
			display: flex;
			align-items: center;
			gap: 10px;
			max-width: 100%;
			min-width: 0;
			background: var(--color-surface);
			padding: 6px 10px 6px 6px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}

		&__document :global(.file-thumb--row) {
			width: 32px;
			height: 32px;
		}
		&__document--checking &__document-meta {
			color: var(--color-warning--onSurface);
		}
		&__document-text {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			min-width: 0;
		}

		&__document-name {
			overflow: hidden;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__document-meta {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
