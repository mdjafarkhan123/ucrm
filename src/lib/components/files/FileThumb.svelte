<script lang="ts">
	import photoIcon from '@tabler/icons/outline/photo.svg?raw';
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
		signedSrc = null,
		size = 'tile'
	}: {
		fileId: string;
		displayName: string;
		mimeType: string;
		kind: FileKind;
		processingState: FileProcessingState;
		hasThumbnail: boolean;
		/** A signed storage link a file list handed out for this exact size, used instead of the route. */
		signedSrc?: string | null;
		/** `tile` for a grid card, `row` for a list line, `panel` for the big preview in the details panel. */
		size?: 'tile' | 'row' | 'panel';
	} = $props();

	// The browser could not fetch a picture that is not available yet, and should not be asked to: pending
	// bytes have not been scanned, and a quarantined file's content is never shown at all.
	const isReady = $derived(processingState === 'available');
	const showsImage = $derived(isReady && kind === 'image');
	// A grid asks for the 480px copy the pipeline made; the panel's large preview asks for the original.
	const routeSource = $derived(fileImageUrl(fileId, size === 'panel' ? 'full' : 'thumb'));
	// A signed link that fails — it expired on a page left open, or storage refused it — falls back to the
	// permanent route once, rather than leaving a broken picture.
	let signedFailed = $state(false);
	const source = $derived(signedSrc && !signedFailed ? signedSrc : routeSource);
	// The thumbnail route falls back to the original on its own, so a backfilled photo with no small copy
	// still draws — it just costs more bytes, which is worth saying out loud rather than hiding.
	const sizeHint = $derived(hasThumbnail || size === 'panel' ? undefined : 'full-size original');

	const extension = $derived(displayName.split('.').pop()?.toUpperCase().slice(0, 5) || 'FILE');
	const family = $derived(
		kind === 'video'
			? 'growth'
			: /^(XLSX?|CSV|ODS)$/.test(extension)
				? 'success'
				: /^(PDF|DOCX?|TXT|RTF|ODT)$/.test(extension) || mimeType === 'application/pdf'
					? 'informative'
					: 'inactive'
	);

	const placeholderIcon = $derived.by(() => {
		if (processingState === 'pending') return clockIcon;
		if (processingState === 'failed' || processingState === 'quarantined') return alertTriangleIcon;
		if (kind === 'image') return photoIcon;
		if (kind === 'video') return videoIcon;
		return fileIcon;
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
	class:file-thumb--pending={processingState === 'pending'}
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
			onerror={() => {
				if (source !== routeSource) signedFailed = true;
			}}
		/>
	{:else if isReady && kind !== 'image'}
		<span
			class="file-thumb__sheet"
			style:--file-color={`var(--color-${family})`}
			aria-label={`${extension} document`}
			><span class="file-thumb__fold"></span><span class="file-thumb__tab">{extension}</span><span
				class="file-thumb__lines"
			></span></span
		>
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
		display: flex;
		flex-direction: column;
		justify-content: center;
		align-items: center;
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
			border-radius: var(--radius-base);
		}
		&--panel {
			aspect-ratio: 4 / 3;
			width: 100%;
			height: 200px;
			aspect-ratio: auto;
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
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		text-align: center;
	}
	.file-thumb--warning .file-thumb__label {
		color: var(--color-critical--onSurface);
	}

	.file-thumb--pending {
		background: var(--color-warning--surface);
	}
	.file-thumb__sheet {
		position: relative;
		flex: 0 0 auto;
		width: 64px;
		height: 84px;
		border: 1px solid var(--color-border);
		border-radius: 6px;
		background: var(--color-white);
		box-shadow: 0 2px 6px color-mix(in srgb, var(--color-heading) 8%, transparent);
	}
	.file-thumb__fold {
		position: absolute;
		right: -1px;
		top: -1px;
		width: 18px;
		height: 18px;
		background: linear-gradient(
			45deg,
			var(--color-surface--background--subtle) 50%,
			var(--color-surface--background) 50%
		);
		border-bottom-left-radius: 4px;
	}
	.file-thumb__tab {
		position: absolute;
		left: -8px;
		top: 24px;
		padding: 2px 6px;
		border-radius: var(--radius-small);
		background: var(--file-color);
		color: var(--color-white);
		font-size: var(--typography--fontSize-overline);
		font-weight: 700;
		letter-spacing: 0.4px;
	}
	.file-thumb__lines {
		position: absolute;
		bottom: 16px;
		left: 12px;
		right: 12px;
		height: 3px;
		background: var(--color-border);
		box-shadow:
			0 -8px var(--color-border),
			0 8px var(--color-border);
	}
	.file-thumb--row .file-thumb__sheet {
		width: 24px;
		height: 30px;
		border-radius: 3px;
	}
	.file-thumb--row .file-thumb__fold {
		width: 8px;
		height: 8px;
	}
	.file-thumb--row .file-thumb__tab {
		top: 10px;
		left: -4px;
		padding: 1px 2px;
		font-size: var(--typography--fontSize-overline);
	}
	.file-thumb--row .file-thumb__lines {
		display: none;
	}
	.file-thumb--panel .file-thumb__sheet {
		width: 104px;
		height: 136px;
		border-radius: var(--radius-base);
	}
	.file-thumb--panel .file-thumb__tab {
		font-size: var(--typography--fontSize-overline);
		top: 40px;
	}
	.file-thumb--pending .file-thumb__icon,
	.file-thumb--warning .file-thumb__icon {
		width: 40px;
		height: 40px;
		border-radius: var(--radius-tile-large);
		background: var(--color-surface);
		:global(svg) {
			width: 20px;
			height: 20px;
		}
	}
	.file-thumb--pending .file-thumb__icon {
		color: var(--color-warning);
	}
	.file-thumb--pending .file-thumb__label {
		color: var(--color-warning--onSurface);
	}
	.file-thumb--row .file-thumb__icon {
		background: transparent;
		width: 24px;
		height: 24px;
		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}
</style>
