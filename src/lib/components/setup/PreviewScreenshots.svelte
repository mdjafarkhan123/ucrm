<script lang="ts">
	import { untrack } from 'svelte';
	import photoPlusIcon from '@tabler/icons/outline/photo-plus.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';
	import Lightbox, { type LightboxItem } from '$lib/components/ui/Lightbox.svelte';
	import { uploadAttachmentFile } from '$lib/collaboration/api';
	import { createImageThumbnail } from '$lib/collaboration/image-thumbnail';
	import {
		PREVIEW_SCREENSHOTS_MAX,
		PREVIEW_SCREENSHOT_BYTES_MAX,
		PREVIEW_SCREENSHOT_TYPES,
		type PreviewScreenshotUpload,
		type PreviewScreenshotUrls
	} from '$lib/setup/preview';

	// Client onboarding E3: screenshots on a preview card (Jafar) or on the client's note. Photos show as photos and
	// open the Lightbox. When editable, each picked photo uploads straight to storage with a small copy, as Chat with
	// Uplift's files do, and joins `value` once it has finished; the save that follows names it.
	let {
		value = $bindable([]),
		urls,
		editable = false,
		onUploadingChange
	}: {
		value?: PreviewScreenshotUpload[];
		urls: PreviewScreenshotUrls;
		editable?: boolean;
		onUploadingChange?: (uploading: boolean) => void;
	} = $props();

	type Upload = { key: string; name: string; progress: number };
	let uploads = $state<Upload[]>([]);
	let error = $state('');
	let input: HTMLInputElement | undefined = $state();
	let lightboxOpen = $state(false);
	let lightboxIndex = $state(0);

	$effect(() => {
		const busy = uploads.length > 0;
		untrack(() => onUploadingChange?.(busy));
	});

	const items = $derived<LightboxItem[]>(
		value.map((shot) => ({
			id: shot.object_key,
			src: urls.view(shot.object_key, 'full'),
			thumbSrc: urls.view(shot.object_key, shot.has_thumbnail ? 'thumb' : 'full'),
			caption: shot.file_name
		}))
	);

	async function presign(file: File) {
		const response = await fetch(urls.presign, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ file_name: file.name, mime_type: file.type, size_bytes: file.size })
		});
		const body = (await response.json().catch(() => ({}))) as {
			upload_url?: string;
			object_key?: string;
			thumbnail_upload_url?: string | null;
			error?: string;
			field_errors?: Record<string, string>;
		};
		if (!response.ok || !body.upload_url || !body.object_key)
			throw new Error(
				Object.values(body.field_errors ?? {})[0] ?? body.error ?? 'That photo could not be added.'
			);
		return body as { upload_url: string; object_key: string; thumbnail_upload_url: string | null };
	}

	async function uploadOne(key: string, file: File) {
		try {
			const ticket = await presign(file);
			await uploadAttachmentFile(ticket.upload_url, file, (fraction) => {
				uploads = uploads.map((each) =>
					each.key === key ? { ...each, progress: fraction } : each
				);
			});
			// The small copy is a nicety: a photo the browser cannot shrink still shows from the original.
			let hasThumbnail = false;
			const thumbnail = ticket.thumbnail_upload_url ? await createImageThumbnail(file) : null;
			if (thumbnail && ticket.thumbnail_upload_url)
				hasThumbnail = await uploadAttachmentFile(ticket.thumbnail_upload_url, thumbnail).then(
					() => true,
					() => false
				);
			value = [
				...value,
				{
					object_key: ticket.object_key,
					file_name: file.name,
					mime_type: file.type,
					has_thumbnail: hasThumbnail
				}
			];
		} catch (failure) {
			error = failure instanceof Error ? failure.message : 'That photo could not be added.';
		} finally {
			uploads = uploads.filter((each) => each.key !== key);
		}
	}

	function pick(files: FileList | null) {
		const picked = Array.from(files ?? []);
		if (input) input.value = '';
		error = '';
		if (value.length + uploads.length + picked.length > PREVIEW_SCREENSHOTS_MAX) {
			error = `Add up to ${PREVIEW_SCREENSHOTS_MAX} screenshots.`;
			return;
		}
		for (const file of picked) {
			if (!(PREVIEW_SCREENSHOT_TYPES as readonly string[]).includes(file.type)) {
				error = 'A screenshot must be a photo (JPG, PNG, WebP or GIF).';
				continue;
			}
			if (file.size > PREVIEW_SCREENSHOT_BYTES_MAX) {
				error = 'Each screenshot must be 10 MB or smaller.';
				continue;
			}
			const key = `${file.name}-${file.size}-${Math.random()}`;
			uploads = [...uploads, { key, name: file.name, progress: 0 }];
			void uploadOne(key, file);
		}
	}

	const canAdd = $derived(editable && value.length + uploads.length < PREVIEW_SCREENSHOTS_MAX);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if value.length > 0 || uploads.length > 0 || editable}
	<div class="preview-shots">
		{#if value.length > 0 || uploads.length > 0}
			<ul class="preview-shots__grid">
				{#each value as shot, index (shot.object_key)}
					<li class="preview-shots__item">
						<button
							type="button"
							class="preview-shots__open"
							aria-label="Open {shot.file_name}"
							onclick={() => {
								lightboxIndex = index;
								lightboxOpen = true;
							}}
						>
							<img
								src={urls.view(shot.object_key, shot.has_thumbnail ? 'thumb' : 'full')}
								alt={shot.file_name}
								loading="lazy"
							/>
						</button>
						{#if editable}
							<button
								type="button"
								class="preview-shots__remove"
								aria-label="Remove {shot.file_name}"
								onclick={() =>
									(value = value.filter((each) => each.object_key !== shot.object_key))}
								>{@html xIcon}</button
							>
						{/if}
					</li>
				{/each}
				{#each uploads as upload (upload.key)}
					<li class="preview-shots__item preview-shots__item--uploading" aria-live="polite">
						<span class="preview-shots__progress"
							>Uploading {Math.round(upload.progress * 100)}%</span
						>
					</li>
				{/each}
			</ul>
		{/if}

		{#if canAdd}
			<label class="preview-shots__add">
				<span class="preview-shots__add-icon" aria-hidden="true">{@html photoPlusIcon}</span>
				Add screenshots
				<input
					bind:this={input}
					type="file"
					accept={PREVIEW_SCREENSHOT_TYPES.join(',')}
					multiple
					onchange={(event) => pick(event.currentTarget.files)}
				/>
			</label>
		{/if}
		{#if error}
			<p class="preview-shots__error" role="alert">{error}</p>
		{/if}
	</div>
{/if}

<Lightbox
	open={lightboxOpen}
	{items}
	bind:index={lightboxIndex}
	onClose={() => (lightboxOpen = false)}
/>

<style lang="scss">
	.preview-shots {
		display: grid;
		gap: var(--space-small);

		&__grid {
			display: grid;
			grid-template-columns: repeat(auto-fill, minmax(96px, 1fr));
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__item {
			position: relative;
			aspect-ratio: 4 / 3;
			overflow: hidden;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);

			&--uploading {
				display: grid;
				place-items: center;
			}
		}

		&__open {
			display: block;
			width: 100%;
			height: 100%;
			padding: 0;
			border: 0;
			background: none;
			cursor: zoom-in;

			img {
				display: block;
				width: 100%;
				height: 100%;
				object-fit: cover;
			}

			&:focus-visible {
				outline: var(--focus-ring, 2px solid var(--color-interactive));
				outline-offset: -2px;
			}
		}

		&__remove {
			position: absolute;
			top: var(--space-smallest);
			right: var(--space-smallest);
			display: grid;
			place-items: center;
			width: 24px;
			height: 24px;
			padding: 0;
			border: 0;
			border-radius: var(--radius-circle, 50%);
			background: rgb(0 0 0 / 60%);
			color: #fff;
			cursor: pointer;

			:global(svg) {
				width: 14px;
				height: 14px;
			}

			&:hover {
				background: rgb(0 0 0 / 80%);
			}

			&:focus-visible {
				outline: 2px solid #fff;
			}
		}

		&__progress {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__add {
			display: inline-flex;
			align-items: center;
			justify-self: start;
			gap: var(--space-smaller);
			padding: var(--space-smaller) var(--space-small);
			border: var(--border-base) dashed var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-interactive);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			cursor: pointer;

			input {
				position: absolute;
				width: 1px;
				height: 1px;
				opacity: 0;
				pointer-events: none;
			}

			&:hover {
				border-color: var(--color-interactive);
			}

			&:focus-within {
				outline: 2px solid var(--color-interactive);
				outline-offset: 2px;
			}
		}

		&__add-icon {
			display: inline-flex;

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
