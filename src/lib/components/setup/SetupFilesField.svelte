<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import Lightbox, { type LightboxItem } from '$lib/components/ui/Lightbox.svelte';
	import { uploadAttachmentFile } from '$lib/collaboration/api';
	import { iconForMimeType } from '$lib/collaboration/file-icons';
	import { MAX_FILE_SIZE_BYTES } from '$lib/files/allowlist';
	import { finishFileUpload, formatFileSize } from '$lib/files/api';
	import {
		fetchSetupFiles,
		setupFileHref,
		setupFilesKey,
		startSetupFileUpload,
		type SetupFileInfo
	} from '$lib/setup/api';
	import {
		setupFileAccept,
		setupFileFormats,
		setupFileIds,
		setupFileKindsPhrase,
		setupFileType,
		type SetupFileKind
	} from '$lib/setup/files';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import cloudUploadIcon from '@tabler/icons/outline/cloud-upload.svg?raw';
	import loaderIcon from '@tabler/icons/outline/loader-2.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	// A photo or file setup answer (client onboarding A5c), laid out like a Google Forms file question: what
	// the question takes, the files added so far, and one button to add more. Each file uploads the moment it
	// is picked (on a phone the picker offers the camera too) through the File Manager's handshake, then joins
	// the answer, which the page saves like any other. The virus check finishes on its own; until it has, the
	// file says it is being checked. Removing a file takes it out of the answer and leaves it in the File library.
	let {
		id,
		factKey,
		fieldKey,
		label,
		kinds,
		maxFiles,
		userId,
		value = $bindable(''),
		invalid = false,
		oncommit
	}: {
		id: string;
		factKey: string;
		/** A5e: the file box of a list question, when this sits in one of its rows. */
		fieldKey?: string;
		label: string;
		kinds: SetupFileKind[];
		maxFiles: number;
		userId: string | null;
		/** The answer: the files' ids as JSON text, or empty. */
		value?: string;
		invalid?: boolean;
		oncommit: () => void;
	} = $props();

	type Upload = { key: string; name: string; progress: number; error: string };

	let input = $state<HTMLInputElement | null>(null);
	let uploads = $state<Upload[]>([]);
	let dragging = $state(false);
	let lightboxOpen = $state(false);
	let lightboxIndex = $state(0);

	const ids = $derived(setupFileIds(value));
	const inFlight = $derived(uploads.filter((upload) => !upload.error).length);
	const room = $derived(maxFiles - ids.length - inFlight);
	const phrase = $derived(setupFileKindsPhrase(kinds));
	const onlyPhotos = $derived(kinds.length === 1 && kinds[0] === 'photo');

	const files = createQuery(() => ({
		queryKey: setupFilesKey(userId, ids),
		queryFn: () => fetchSetupFiles(ids),
		enabled: ids.length > 0,
		// The previous list stays on screen while the new one loads, so adding a file never blanks the others.
		placeholderData: (previous: SetupFileInfo[] | undefined) => previous,
		// Checked again every few seconds while a file is still going through the virus check (about a
		// minute), and within the hour the signed previews last otherwise.
		refetchInterval: (query) =>
			query.state.data?.some((file) => file.state === 'checking') ? 4000 : 30 * 60 * 1000
	}));

	const byId = $derived(new Map((files.data ?? []).map((file) => [file.id, file])));
	const photos = $derived(
		ids
			.map((fileId) => byId.get(fileId))
			.filter((file): file is SetupFileInfo => file?.state === 'ready' && Boolean(file.thumb_url))
	);
	const lightboxItems = $derived<LightboxItem[]>(
		photos.map((file) => ({
			id: file.id,
			src: setupFileHref(file.id),
			thumbSrc: file.thumb_url ?? setupFileHref(file.id),
			caption: file.name
		}))
	);

	function writeIds(next: string[]) {
		value = next.length ? JSON.stringify(next) : '';
		oncommit();
	}

	function remove(fileId: string) {
		writeIds(ids.filter((existing) => existing !== fileId));
	}

	function patch(key: string, changes: Partial<Upload>) {
		uploads = uploads.map((upload) => (upload.key === key ? { ...upload, ...changes } : upload));
	}

	function addFiles(fileList: FileList | File[] | null) {
		if (!fileList) return;
		let left = room;
		for (const file of Array.from(fileList)) {
			const key = `${file.name}-${file.size}-${Date.now()}-${Math.random()}`;
			const refusal = !setupFileType(file.name, kinds)
				? `This question takes ${phrase}: ${setupFileFormats(kinds)}.`
				: file.size > MAX_FILE_SIZE_BYTES
					? 'Files can be up to 100 MB.'
					: file.size === 0
						? 'That file is empty.'
						: left <= 0
							? maxFiles === 1
								? 'This question takes one file. Remove the one here to add another.'
								: `This question takes up to ${maxFiles} files.`
							: '';
			uploads = [...uploads, { key, name: file.name, progress: 0, error: refusal }];
			if (!refusal) {
				left -= 1;
				void upload(key, file);
			}
		}
	}

	async function upload(key: string, file: File) {
		try {
			const started = await startSetupFileUpload(factKey, file, fieldKey);
			let shown = -1;
			// The signed upload names one type for each kind of file; a slice carries the bytes under it.
			await uploadAttachmentFile(
				started.upload_url,
				file.slice(0, file.size, started.mime_type),
				(fraction) => {
					const percent = Math.round(fraction * 100);
					if (percent === shown) return;
					shown = percent;
					patch(key, { progress: fraction });
				}
			);
			await finishFileUpload(started.file_id);
			uploads = uploads.filter((upload) => upload.key !== key);
			// Read now, at the end, so files finishing together each add to what the others left.
			writeIds([...setupFileIds(value), started.file_id]);
		} catch (error) {
			patch(key, {
				progress: 0,
				error: error instanceof Error ? error.message : 'That file could not be uploaded.'
			});
		}
	}

	function dismiss(key: string) {
		uploads = uploads.filter((upload) => upload.key !== key);
	}

	function openPhoto(fileId: string) {
		lightboxIndex = Math.max(
			0,
			photos.findIndex((file) => file.id === fileId)
		);
		lightboxOpen = true;
	}

	function status(file: SetupFileInfo | undefined) {
		if (!file || file.state === 'checking') return 'Checking for viruses…';
		if (file.state === 'ready') return formatFileSize(file.size_bytes);
		if (file.state === 'removed') return 'Removed from your files. Remove it here too.';
		return `${file.problem ?? 'This file could not be accepted.'} Remove it and try another.`;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<fieldset class="setup-files">
	<legend class="setup-files__label">{label}</legend>
	<p class="setup-files__limit">
		{maxFiles === 1 ? 'One file' : `Up to ${maxFiles} files`} · {setupFileFormats(kinds)} · up to 100
		MB each
	</p>

	<!-- Dropping is a shortcut for the Add button beside it, which stays the way in for keyboards and phones. -->
	<div
		class="setup-files__box"
		class:setup-files__box--dragging={dragging}
		class:setup-files__box--invalid={invalid}
		role="group"
		aria-label={`Files for ${label}`}
		ondragover={(event) => {
			if (room <= 0) return;
			event.preventDefault();
			dragging = true;
		}}
		ondragleave={() => (dragging = false)}
		ondrop={(event) => {
			event.preventDefault();
			dragging = false;
			addFiles(event.dataTransfer?.files ?? null);
		}}
	>
		{#if ids.length > 0 || uploads.length > 0}
			<ul class="setup-files__list">
				{#each ids as fileId (fileId)}
					{@const file = byId.get(fileId)}
					{@const problem = file?.state === 'refused' || file?.state === 'removed'}
					<li class="setup-files__item" class:setup-files__item--problem={problem}>
						{#if file?.state === 'ready' && file.thumb_url}
							<button
								type="button"
								class="setup-files__thumb"
								aria-label={`View ${file.name}`}
								onclick={() => openPhoto(fileId)}
							>
								<img src={file.thumb_url} alt="" loading="lazy" />
							</button>
						{:else}
							<span
								class="setup-files__icon"
								class:setup-files__icon--spinning={!file || file.state === 'checking'}
								aria-hidden="true"
							>
								{@html problem
									? alertTriangleIcon
									: !file || file.state === 'checking'
										? loaderIcon
										: iconForMimeType(file.mime_type)}
							</span>
						{/if}
						<span class="setup-files__text">
							{#if file?.state === 'ready'}
								<a
									class="setup-files__name"
									href={setupFileHref(fileId)}
									target="_blank"
									rel="noopener noreferrer">{file.name}</a
								>
							{:else}
								<span class="setup-files__name">{file?.name ?? 'Your file'}</span>
							{/if}
							<span class="setup-files__meta" role={problem ? 'alert' : undefined}
								>{status(file)}</span
							>
						</span>
						<button
							type="button"
							class="setup-files__remove"
							aria-label={`Remove ${file?.name ?? 'this file'}`}
							onclick={() => remove(fileId)}
						>
							{@html xIcon}
						</button>
					</li>
				{/each}
				{#each uploads as upload (upload.key)}
					<li class="setup-files__item" class:setup-files__item--problem={Boolean(upload.error)}>
						<span
							class="setup-files__icon"
							class:setup-files__icon--spinning={!upload.error}
							aria-hidden="true"
						>
							{@html upload.error ? alertTriangleIcon : loaderIcon}
						</span>
						<span class="setup-files__text">
							<span class="setup-files__name">{upload.name}</span>
							<span class="setup-files__meta" role={upload.error ? 'alert' : undefined}>
								{upload.error || `Uploading ${Math.round(upload.progress * 100)}%`}
							</span>
						</span>
						{#if upload.error}
							<button
								type="button"
								class="setup-files__remove"
								aria-label={`Dismiss ${upload.name}`}
								onclick={() => dismiss(upload.key)}
							>
								{@html xIcon}
							</button>
						{:else}
							<span
								class="setup-files__progress"
								style:width={`${Math.round(upload.progress * 100)}%`}
								aria-hidden="true"
							></span>
						{/if}
					</li>
				{/each}
			</ul>
		{/if}

		<input
			bind:this={input}
			id={`${id}-input`}
			class="setup-files__input"
			type="file"
			multiple={maxFiles > 1}
			accept={setupFileAccept(kinds)}
			tabindex="-1"
			aria-hidden="true"
			onchange={(event) => {
				addFiles(event.currentTarget.files);
				event.currentTarget.value = '';
			}}
		/>
		<div class="setup-files__add">
			<Button variant="secondary" size="small" disabled={room <= 0} onclick={() => input?.click()}>
				<span class="setup-files__button-icon" aria-hidden="true">{@html cloudUploadIcon}</span>
				{onlyPhotos
					? maxFiles === 1
						? 'Add a photo'
						: 'Add photos'
					: maxFiles === 1
						? 'Add a file'
						: `Add ${phrase}`}
			</Button>
			<span class="setup-files__drop">or drop {maxFiles === 1 ? 'it' : 'them'} here</span>
		</div>
	</div>
</fieldset>

<Lightbox
	open={lightboxOpen}
	items={lightboxItems}
	bind:index={lightboxIndex}
	onClose={() => (lightboxOpen = false)}
/>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.setup-files {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		min-width: 0;
		margin: 0;
		padding: 0;
		border: 0;

		&__label {
			margin-bottom: var(--space-small);
			padding: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__box {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding: var(--space-base);
			border: var(--border-base) dashed var(--color-border);
			border-radius: var(--radius-base);
			transition:
				border-color var(--timing-quick) ease-out,
				background-color var(--timing-quick) ease-out;

			&--dragging {
				border-color: var(--color-border--interactive);
				background: var(--color-surface--background);
			}

			&--invalid {
				border-color: var(--color-critical);
			}
		}

		&__limit {
			margin: calc(var(--space-small) * -1) 0 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__item {
			position: relative;
			display: flex;
			align-items: center;
			gap: var(--space-small);
			min-height: 56px;
			padding: var(--space-smaller) var(--space-small);
			overflow: hidden;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);

			&--problem {
				border-color: var(--color-critical);
			}
		}

		&__thumb {
			flex: 0 0 auto;
			width: 44px;
			height: 44px;
			padding: 0;
			overflow: hidden;
			border: 0;
			border-radius: var(--radius-small);
			background: var(--color-surface--background);
			cursor: zoom-in;

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			img {
				display: block;
				width: 100%;
				height: 100%;
				object-fit: cover;
			}
		}

		&__icon {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			width: 44px;
			height: 44px;
			border-radius: var(--radius-small);
			background: var(--color-surface--background);
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 22px;
				height: 22px;
			}

			&--spinning :global(svg) {
				animation: setup-files-spin 1s linear infinite;
			}
		}

		&__item--problem &__icon {
			color: var(--color-critical);
		}

		&__text {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			gap: 2px;
			min-width: 0;
		}

		&__name {
			overflow: hidden;
			color: var(--color-heading);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		a.setup-files__name {
			color: var(--color-interactive);
			text-decoration: none;

			&:hover {
				text-decoration: underline;
			}
		}

		&__meta {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__item--problem &__meta {
			color: var(--color-critical--onSurface);
		}

		&__remove {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			width: 32px;
			height: 32px;
			padding: 0;
			border: var(--border-base) solid transparent;
			border-radius: var(--radius-base);
			background: none;
			color: var(--color-icon--secondary);
			cursor: pointer;
			transition: all var(--timing-quick) ease-out;

			&:hover,
			&:focus-visible {
				border-color: var(--color-critical);
				color: var(--color-critical);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__progress {
			position: absolute;
			bottom: 0;
			left: 0;
			height: 3px;
			background: var(--color-interactive);
			transition: width var(--timing-quick) ease-out;
		}

		&__input {
			display: none;
		}

		&__add {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}

		&__button-icon {
			display: inline-grid;
			place-items: center;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__drop {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	@keyframes setup-files-spin {
		to {
			transform: rotate(360deg);
		}
	}

	@media (hover: none) {
		.setup-files__drop {
			display: none;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.setup-files__icon--spinning :global(svg) {
			animation: none;
		}
	}
</style>
