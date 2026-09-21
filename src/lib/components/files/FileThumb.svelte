<script lang="ts">
	import photoIcon from '@tabler/icons/outline/photo.svg?raw';
	import fileTypePdfIcon from '@tabler/icons/outline/file-type-pdf.svg?raw';
	import fileTypeDocIcon from '@tabler/icons/outline/file-type-doc.svg?raw';
	import fileTypeXlsIcon from '@tabler/icons/outline/file-type-xls.svg?raw';
	import fileTypeCsvIcon from '@tabler/icons/outline/file-type-csv.svg?raw';
	import fileTypeTxtIcon from '@tabler/icons/outline/file-type-txt.svg?raw';
	import videoIcon from '@tabler/icons/outline/video.svg?raw';
	import fileIcon from '@tabler/icons/outline/file.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import { fileImageUrl, type FileKind, type FileProcessingState } from '$lib/files/api';

	// One file's picture, or the icon that stands in for one. Photos show as photos wherever they appear;
	// a document keeps a typed icon rather than a grey square, so a PDF is recognisable at a glance.
	let {
		fileId,
		displayName,
		mimeType,
		kind,
		processingState,
		hasThumbnail,
		size = 'tile'
	}: {
		fileId: string;
		displayName: string;
		mimeType: string;
		kind: FileKind;
		processingState: FileProcessingState;
		hasThumbnail: boolean;
		/** `tile` for a grid card, `row` for a list line, `panel` for the big preview in the details panel. */
		size?: 'tile' | 'row' | 'panel';
	} = $props();

	// The browser could not fetch a picture that is not available yet, and should not be asked to: pending
	// bytes have not been scanned, and a quarantined file's content is never shown at all.
	const isReady = $derived(processingState === 'available');
	const showsImage = $derived(isReady && kind === 'image');
	// A grid asks for the 480px copy the pipeline made; the panel's large preview asks for the original.
	const source = $derived(fileImageUrl(fileId, size === 'panel' ? 'full' : 'thumb'));
	// The thumbnail route falls back to the original on its own, so a backfilled photo with no small copy
	// still draws — it just costs more bytes, which is worth saying out loud rather than hiding.
	const sizeHint = $derived(hasThumbnail || size === 'panel' ? undefined : 'full-size original');

	function documentIcon(type: string, name: string) {
		const extension = name.toLowerCase().split('.').pop() ?? '';
		if (type === 'application/pdf' || extension === 'pdf') return fileTypePdfIcon;
		if (extension === 'doc' || extension === 'docx') return fileTypeDocIcon;
		if (extension === 'xls' || extension === 'xlsx') return fileTypeXlsIcon;
		if (extension === 'csv') return fileTypeCsvIcon;
		if (extension === 'txt') return fileTypeTxtIcon;
		return fileIcon;
	}

	const placeholderIcon = $derived.by(() => {
		if (processingState === 'pending') return clockIcon;
		if (processingState === 'failed' || processingState === 'quarantined') return alertTriangleIcon;
		if (kind === 'image') return photoIcon;
		if (kind === 'video') return videoIcon;
		return documentIcon(mimeType, displayName);
	});

	const placeholderLabel = $derived.by(() => {
		if (processingState === 'pending') return 'Still being checked';
		if (processingState === 'quarantined') return 'Blocked by the virus scan';
		if (processingState === 'failed') return 'Upload failed';
		return '';
	});
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div
	class="file-thumb file-thumb--{size}"
	class:file-thumb--warning={processingState === 'failed' || processingState === 'quarantined'}
>
	{#if showsImage}
		<img
			class="file-thumb__image"
			src={source}
			alt={displayName}
			title={sizeHint}
			loading="lazy"
			decoding="async"
		/>
	{:else}
		<span class="file-thumb__icon" aria-hidden="true">{@html placeholderIcon}</span>
		{#if placeholderLabel && size !== 'row'}
			<span class="file-thumb__label">{placeholderLabel}</span>
		{/if}
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.file-thumb {
		display: grid;
		place-items: center;
		gap: var(--space-small);
		overflow: hidden;
		border-radius: var(--radius-base);
		background: var(--color-surface--background);

		&--tile {
			aspect-ratio: 4 / 3;
			width: 100%;
		}
		&--row {
			flex: 0 0 auto;
			width: 40px;
			height: 40px;
			border-radius: var(--radius-small);
		}
		&--panel {
			aspect-ratio: 4 / 3;
			width: 100%;
			max-height: 320px;
		}
		&--warning {
			background: var(--color-critical--surface);
		}
	}

	.file-thumb__image {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}

	.file-thumb__icon {
		display: grid;
		place-items: center;
		color: var(--color-icon--secondary);

		:global(svg) {
			width: 28px;
			height: 28px;
		}
	}
	.file-thumb--row .file-thumb__icon :global(svg) {
		width: 20px;
		height: 20px;
	}
	.file-thumb--panel .file-thumb__icon :global(svg) {
		width: 48px;
		height: 48px;
	}
	.file-thumb--warning .file-thumb__icon {
		color: var(--color-critical--onSurface);
	}

	.file-thumb__label {
		padding: 0 var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		text-align: center;
	}
	.file-thumb--warning .file-thumb__label {
		color: var(--color-critical--onSurface);
	}
</style>
