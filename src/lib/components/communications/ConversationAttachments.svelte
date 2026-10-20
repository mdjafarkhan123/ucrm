<script lang="ts">
	import { untrack } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { uploadAttachmentFile } from '$lib/collaboration/api';
	import { createImageThumbnail } from '$lib/collaboration/image-thumbnail';
	import { formatFileSize } from '$lib/collaboration/format';
	import FileThumb from '$lib/components/files/FileThumb.svelte';
	import {
		MAX_OUTBOUND_ATTACHMENTS,
		OUTBOUND_ATTACHMENT_TOTAL_SIZE_BYTES,
		MAX_SMS_ATTACHMENTS_PER_MESSAGE,
		isDangerousAttachmentName
	} from '$lib/communications/attachment-limits';
	import {
		presignOutboundAttachment,
		type OutboundAttachmentPayload
	} from '$lib/communications/inbox';
	import paperclipIcon from '@tabler/icons/outline/paperclip.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import alertCircleIcon from '@tabler/icons/outline/alert-circle.svg?raw';

	// The composer's paperclip: shared by ConversationComposer and ManualEmailDialog so both send paths
	// attach files the same way. Files upload immediately on pick (presign + PUT), before Send is ever
	// pressed -- Send just forwards the object keys getAttachments() already resolved. The caller reads
	// getAttachments() at send time and calls reset() after a successful send.
	//
	// Stage 6D-2/6D-3: `variant="sms"` reuses the same upload flow for the composer's "attach a file" on
	// SMS instead of forking a second component (Rule 8) -- only the caps, prefix-channel and labels change.
	// Any common file type is accepted: a picture goes as real MMS when the sender/destination allow it,
	// otherwise the text carries a secure link instead, so there is no client-side mime whitelist for SMS.
	//
	// Chat with Uplift reuses it too (onboarding D4b), on both sides: `presign` swaps in that chat's own
	// upload route and `maxFiles` its cap. When the route also hands back somewhere for a photo's small copy,
	// one is made here and uploaded beside the original.
	let {
		disabled = false,
		variant = 'email',
		presign,
		maxFiles,
		triggerFirst = false,
		cardsTarget = null,
		onUploadingChange,
		onReadyChange
	}: {
		disabled?: boolean;
		variant?: 'email' | 'sms';
		/** Asks a different route for the upload link. Left out, the customer inbox's own is used. */
		presign?: (file: { fileName: string; mimeType: string; sizeBytes: number }) => Promise<{
			upload_url: string;
			object_key: string;
			thumbnail_upload_url?: string | null;
		}>;
		/** How many files one message may carry, when it differs from the variant's own cap. */
		maxFiles?: number;
		/** Keeps the paperclip in front of the files, so it does not move as they are added. */
		triggerFirst?: boolean;
		/** Where the file cards go: under the message words, inside the writing area. The paperclip stays
		 *  where this component is mounted (the footer). Left out, the cards sit beside the paperclip. */
		cardsTarget?: HTMLElement | null;
		onUploadingChange?: (uploading: boolean) => void;
		/** How many files have finished uploading and would go with a send. */
		onReadyChange?: (count: number) => void;
	} = $props();

	const isSms = $derived(variant === 'sms');
	const maxAttachments = $derived(
		maxFiles ?? (isSms ? MAX_SMS_ATTACHMENTS_PER_MESSAGE : MAX_OUTBOUND_ATTACHMENTS)
	);
	const maxTotalBytes = OUTBOUND_ATTACHMENT_TOTAL_SIZE_BYTES;
	const tooManyMessage = $derived(
		maxFiles
			? `Attach at most ${maxFiles} files to one message.`
			: isSms
				? 'Attach at most one file to a text message.'
				: `Attach at most ${MAX_OUTBOUND_ATTACHMENTS} files to one email.`
	);
	const tooLargeMessage = $derived(
		isSms
			? 'A file must be 20 MB or smaller to send as a text message.'
			: 'Attachments must total 20 MB or less.'
	);
	const triggerLabel = $derived(isSms ? 'Attach a file' : 'Attach files');

	type Item = {
		key: string;
		file: File;
		status: 'uploading' | 'done' | 'error';
		progress: number;
		error: string;
		objectKey: string | null;
		hasThumbnail: boolean;
		/** A picture's own pixels, for its card, until it is removed. */
		previewUrl: string | null;
	};

	let items = $state<Item[]>([]);
	let rejectionError = $state('');
	let fileInputEl: HTMLInputElement | undefined = $state();
	const uid = $props.id();
	const pickerId = `${uid}-attach`;

	const anyUploading = $derived(items.some((item) => item.status === 'uploading'));

	// Reports upload state to the composer, which disables Send while it is true. Runs untracked so the
	// composer's own state write here never comes back around as a dependency of this effect.
	$effect(() => {
		const uploading = anyUploading;
		untrack(() => onUploadingChange?.(uploading));
	});

	const readyCount = $derived(items.filter((item) => item.status === 'done').length);
	$effect(() => {
		const count = readyCount;
		untrack(() => onReadyChange?.(count));
	});

	function patch(key: string, changes: Partial<Item>) {
		items = items.map((item) => (item.key === key ? { ...item, ...changes } : item));
	}

	async function uploadOne(key: string, file: File) {
		try {
			const claim = {
				fileName: file.name,
				mimeType: file.type || 'application/octet-stream',
				sizeBytes: file.size
			};
			const presigned: Awaited<ReturnType<NonNullable<typeof presign>>> = presign
				? await presign(claim)
				: await presignOutboundAttachment({ ...claim, channel: isSms ? 'sms' : 'email' });
			let shownPercent = -1;
			await uploadAttachmentFile(presigned.upload_url, file, (fraction) => {
				const percent = Math.round(fraction * 100);
				if (percent === shownPercent) return;
				shownPercent = percent;
				patch(key, { progress: fraction });
			});
			// The small copy is a nicety: a photo the browser cannot shrink, or a copy that fails to upload,
			// still sends, and is shown from the original instead.
			let hasThumbnail = false;
			if (presigned.thumbnail_upload_url) {
				const thumbnail = await createImageThumbnail(file);
				if (thumbnail) {
					hasThumbnail = await uploadAttachmentFile(presigned.thumbnail_upload_url, thumbnail).then(
						() => true,
						() => false
					);
				}
			}
			patch(key, { status: 'done', objectKey: presigned.object_key, progress: 1, hasThumbnail });
		} catch (error) {
			const message = error instanceof Error ? error.message : 'That file could not be uploaded.';
			patch(key, { status: 'error', error: message });
		}
	}

	/** Attaches files that did not come from the picker — pasted into the message box, say. */
	export function add(files: File[]) {
		addFiles(files);
	}

	function addFiles(fileList: FileList | File[] | null) {
		// The reset has to come after reading the files: Chrome hands back a live FileList tied to the
		// input, so clearing `.value` first empties this same reference before it can be read.
		if (!fileList || disabled) {
			if (fileInputEl) fileInputEl.value = '';
			return;
		}
		rejectionError = '';

		const incoming = Array.from(fileList);
		const existing = items.filter((item) => item.status !== 'error');
		if (existing.length + incoming.length > maxAttachments) {
			rejectionError = tooManyMessage;
			if (fileInputEl) fileInputEl.value = '';
			return;
		}

		let runningTotal = existing.reduce((sum, item) => sum + item.file.size, 0);
		for (const file of incoming) {
			if (isDangerousAttachmentName(file.name)) {
				rejectionError = 'That file type is not allowed.';
				continue;
			}
			runningTotal += file.size;
			if (runningTotal > maxTotalBytes) {
				rejectionError = tooLargeMessage;
				continue;
			}
			const key = `${file.name}-${file.size}-${Date.now()}-${Math.random()}`;
			items.push({
				key,
				file,
				status: 'uploading',
				progress: 0,
				error: '',
				objectKey: null,
				hasThumbnail: false,
				previewUrl: file.type.startsWith('image/') ? URL.createObjectURL(file) : null
			});
			void uploadOne(key, file);
		}
		if (fileInputEl) fileInputEl.value = '';
	}

	function remove(key: string) {
		const item = items.find((entry) => entry.key === key);
		if (item?.previewUrl) URL.revokeObjectURL(item.previewUrl);
		items = items.filter((entry) => entry.key !== key);
	}

	// "PDF · 182 KB", "Photo · 2.4 MB".
	function typeLabel(file: File) {
		if (file.type.startsWith('image/')) return 'Photo';
		if (file.type.startsWith('video/')) return 'Video';
		if (file.type === 'application/pdf') return 'PDF';
		const extension = file.name.includes('.') ? file.name.split('.').pop()?.toUpperCase() : '';
		return extension || 'File';
	}

	function kindOf(file: File) {
		if (file.type.startsWith('image/')) return 'image' as const;
		if (file.type.startsWith('video/')) return 'video' as const;
		return 'document' as const;
	}

	// Moves the cards into the caller's writing area. Svelte still owns the nodes; only where they hang
	// changes, so they keep updating and are removed with this component.
	function placeIn(target: HTMLElement | null) {
		return (element: HTMLElement) => {
			if (!target) return;
			target.appendChild(element);
			return () => element.remove();
		};
	}

	/** The resolved payload the send routes accept -- only files that finished uploading. */
	export function getAttachments(): (OutboundAttachmentPayload & { has_thumbnail?: boolean })[] {
		return items
			.filter(
				(item): item is Item & { objectKey: string } =>
					item.status === 'done' && item.objectKey !== null
			)
			.map((item) => ({
				object_key: item.objectKey,
				file_name: item.file.name,
				mime_type: item.file.type || 'application/octet-stream',
				...(item.hasThumbnail ? { has_thumbnail: true } : {})
			}));
	}

	/** Clears every attached file, for a composer that just sent or was cancelled. */
	export function reset() {
		for (const item of items) if (item.previewUrl) URL.revokeObjectURL(item.previewUrl);
		items = [];
		rejectionError = '';
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<!-- `display: contents` keeps this wrapper invisible to layout, so the paperclip acts as a direct flex item
     of whatever footer this is mounted in. The cards go to `cardsTarget`, under the message words. -->
<div class="conversation-attachments">
	{#if items.length > 0 || rejectionError}
		<div
			class="conversation-attachments__files"
			class:conversation-attachments__files--sending={disabled}
			class:conversation-attachments__files--placed={Boolean(cardsTarget)}
			{@attach placeIn(cardsTarget)}
		>
			{#if items.length > 0}
				<ul class="conversation-attachments__cards">
					{#each items as item (item.key)}
						<li
							class="conversation-attachments__card"
							class:conversation-attachments__card--error={item.status === 'error'}
						>
							{#if item.status === 'error'}
								<span class="conversation-attachments__failed" aria-hidden="true"
									>{@html alertTriangleIcon}</span
								>
							{:else}
								<FileThumb
									fileId={item.key}
									displayName={item.file.name}
									mimeType={item.file.type}
									kind={kindOf(item.file)}
									processingState="available"
									hasThumbnail
									signedSrc={item.previewUrl}
									size="row"
								/>
							{/if}
							<span class="conversation-attachments__text">
								<span class="conversation-attachments__name" title={item.file.name}
									>{item.file.name}</span
								>
								{#if item.status === 'uploading'}
									<span class="conversation-attachments__meta conversation-attachments__meta--uploading">
										Uploading · {Math.round(item.progress * 100)}%
									</span>
								{:else if item.status === 'error'}
									<span class="conversation-attachments__meta conversation-attachments__meta--error"
										>{item.error}</span
									>
								{:else}
									<span class="conversation-attachments__meta"
										>{typeLabel(item.file)} · {formatFileSize(item.file.size)}</span
									>
								{/if}
							</span>
							<button
								type="button"
								class="conversation-attachments__remove"
								aria-label={`Remove ${item.file.name}`}
								{disabled}
								onclick={() => remove(item.key)}
							>
								{@html xIcon}
							</button>
							{#if item.status === 'uploading'}
								<span class="conversation-attachments__bar" aria-hidden="true">
									<span style={`width: ${Math.round(item.progress * 100)}%`}></span>
								</span>
							{/if}
						</li>
					{/each}
				</ul>
			{/if}
			{#if rejectionError}
				<p class="conversation-attachments__error" role="alert">
					<span aria-hidden="true">{@html alertCircleIcon}</span>{rejectionError}
				</p>
			{/if}
		</div>
	{/if}
	<input
		bind:this={fileInputEl}
		type="file"
		multiple={!isSms}
		id={pickerId}
		class="conversation-attachments__input"
		{disabled}
		onchange={(event) => addFiles((event.currentTarget as HTMLInputElement).files)}
	/>
	<Button
		variant="secondary"
		size="small"
		iconOnly
		class={triggerFirst ? 'conversation-attachments__trigger--first' : ''}
		label={triggerLabel}
		{disabled}
		onclick={() => fileInputEl?.click()}
	>
		{@html paperclipIcon}
	</Button>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// Files on a message (`files.md`, board `mZdBv` B): cards two across under the message words.
	.conversation-attachments {
		display: contents;

		&__input {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip: rect(0 0 0 0);
			white-space: nowrap;
		}

		:global(.conversation-attachments__trigger--first) {
			order: -1;
		}

		&__files {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			flex-basis: 100%;
			min-width: 0;

			&--sending .conversation-attachments__card {
				opacity: 0.55;
			}
		}

		&__cards {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__card {
			position: relative;
			display: flex;
			height: 60px;
			box-sizing: border-box;
			align-items: center;
			gap: var(--space-slim);
			padding: 0 32px 0 10px;
			overflow: hidden;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-large);
			background: var(--color-surface);
			box-shadow: var(--shadow-button);

			:global(.file-thumb--row img) {
				box-sizing: border-box;
				border: var(--border-base) solid var(--color-border);
				border-radius: var(--radius-base);
			}

			&--error {
				border: 1.5px solid var(--color-critical);
			}
		}

		&__failed {
			display: grid;
			width: 40px;
			height: 40px;
			flex: 0 0 auto;
			place-items: center;
			border-radius: var(--radius-base);
			color: var(--color-critical);
			background: var(--color-critical--surface);

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__text {
			display: flex;
			min-width: 0;
			flex-direction: column;
			gap: 2px;
		}

		&__name {
			overflow: hidden;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__meta {
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			text-overflow: ellipsis;
			white-space: nowrap;

			&--uploading {
				color: var(--color-interactive);
				font-weight: 600;
			}

			&--error {
				color: var(--color-critical--onSurface);
				font-weight: 600;
			}
		}

		&__remove {
			position: absolute;
			top: 6px;
			right: 6px;
			display: grid;
			width: 22px;
			height: 22px;
			box-sizing: border-box;
			place-items: center;
			padding: 0;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			color: var(--color-icon);
			background: var(--color-surface);
			box-shadow: 0 1px 3px color-mix(in srgb, var(--color-heading) 12%, transparent);
			cursor: pointer;

			:global(svg) {
				display: block;
				width: 12px;
				height: 12px;
			}

			&:hover:not(:disabled) {
				color: var(--color-heading);
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			&:disabled {
				cursor: not-allowed;
			}
		}

		&__bar {
			position: absolute;
			right: 0;
			bottom: 0;
			left: 0;
			height: 4px;
			background: var(--color-surface--background);

			span {
				display: block;
				height: 100%;
				background: var(--color-interactive);
				transition: width var(--timing-quick);
			}
		}

		&__error {
			display: flex;
			align-items: center;
			gap: 6px;
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			:global(svg) {
				display: block;
				width: 14px;
				height: 14px;
			}
		}
	}
</style>
