<script lang="ts">
	import { untrack } from 'svelte';
	import { uploadAttachmentFile } from '$lib/collaboration/api';
	import { formatFileSize } from '$lib/collaboration/format';
	import { iconForMimeType } from '$lib/collaboration/file-icons';
	import {
		MAX_OUTBOUND_ATTACHMENTS,
		OUTBOUND_ATTACHMENT_TOTAL_SIZE_BYTES,
		isDangerousAttachmentName
	} from '$lib/communications/attachment-limits';
	import {
		presignOutboundAttachment,
		type OutboundAttachmentPayload
	} from '$lib/communications/inbox';
	import paperclipIcon from '@tabler/icons/outline/paperclip.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	// The composer's paperclip: shared by ConversationComposer and ManualEmailDialog so both send paths
	// attach files the same way. Files upload immediately on pick (presign + PUT), before Send is ever
	// pressed -- Send just forwards the object keys getAttachments() already resolved. The caller reads
	// getAttachments() at send time and calls reset() after a successful send.
	let {
		disabled = false,
		onUploadingChange
	}: {
		disabled?: boolean;
		onUploadingChange?: (uploading: boolean) => void;
	} = $props();

	type Item = {
		key: string;
		file: File;
		status: 'uploading' | 'done' | 'error';
		progress: number;
		error: string;
		objectKey: string | null;
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

	function patch(key: string, changes: Partial<Item>) {
		items = items.map((item) => (item.key === key ? { ...item, ...changes } : item));
	}

	async function uploadOne(key: string, file: File) {
		try {
			const presigned = await presignOutboundAttachment({
				fileName: file.name,
				mimeType: file.type || 'application/octet-stream',
				sizeBytes: file.size
			});
			let shownPercent = -1;
			await uploadAttachmentFile(presigned.upload_url, file, (fraction) => {
				const percent = Math.round(fraction * 100);
				if (percent === shownPercent) return;
				shownPercent = percent;
				patch(key, { progress: fraction });
			});
			patch(key, { status: 'done', objectKey: presigned.object_key, progress: 1 });
		} catch (error) {
			const message = error instanceof Error ? error.message : 'That file could not be uploaded.';
			patch(key, { status: 'error', error: message });
		}
	}

	function addFiles(fileList: FileList | null) {
		// The reset has to come after reading the files: Chrome hands back a live FileList tied to the
		// input, so clearing `.value` first empties this same reference before it can be read.
		if (!fileList || disabled) {
			if (fileInputEl) fileInputEl.value = '';
			return;
		}
		rejectionError = '';

		const incoming = Array.from(fileList);
		const existing = items.filter((item) => item.status !== 'error');
		if (existing.length + incoming.length > MAX_OUTBOUND_ATTACHMENTS) {
			rejectionError = `Attach at most ${MAX_OUTBOUND_ATTACHMENTS} files to one email.`;
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
			if (runningTotal > OUTBOUND_ATTACHMENT_TOTAL_SIZE_BYTES) {
				rejectionError = 'Attachments must total 20 MB or less.';
				continue;
			}
			const key = `${file.name}-${file.size}-${Date.now()}-${Math.random()}`;
			items.push({ key, file, status: 'uploading', progress: 0, error: '', objectKey: null });
			void uploadOne(key, file);
		}
		if (fileInputEl) fileInputEl.value = '';
	}

	function remove(key: string) {
		items = items.filter((item) => item.key !== key);
	}

	/** The resolved payload the send routes accept -- only files that finished uploading. */
	export function getAttachments(): OutboundAttachmentPayload[] {
		return items
			.filter(
				(item): item is Item & { objectKey: string } =>
					item.status === 'done' && item.objectKey !== null
			)
			.map((item) => ({
				object_key: item.objectKey,
				file_name: item.file.name,
				mime_type: item.file.type || 'application/octet-stream'
			}));
	}

	/** Clears every attached file, for a composer that just sent or was cancelled. */
	export function reset() {
		items = [];
		rejectionError = '';
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<!-- `display: contents` below keeps this wrapper invisible to layout, so the chips and trigger act as
     direct flex items of whatever footer this is mounted in, while still giving the SCSS below a real
     element to scope its selectors against. -->
<div class="conversation-attachments">
	{#each items as item (item.key)}
		<span
			class="conversation-attachments__chip"
			class:conversation-attachments__chip--error={item.status === 'error'}
		>
			<span class="conversation-attachments__chip-icon" aria-hidden="true"
				>{@html iconForMimeType(item.file.type)}</span
			>
			<span class="conversation-attachments__chip-name" title={item.file.name}
				>{item.file.name}</span
			>
			<span class="conversation-attachments__chip-meta">
				{#if item.status === 'uploading'}
					Uploading… {Math.round(item.progress * 100)}%
				{:else if item.status === 'error'}
					{item.error}
				{:else}
					{formatFileSize(item.file.size)}
				{/if}
			</span>
			<button
				type="button"
				class="conversation-attachments__chip-remove"
				aria-label={`Remove ${item.file.name}`}
				{disabled}
				onclick={() => remove(item.key)}
			>
				{@html xIcon}
			</button>
		</span>
	{/each}
	<input
		bind:this={fileInputEl}
		type="file"
		multiple
		id={pickerId}
		class="conversation-attachments__input"
		{disabled}
		onchange={(event) => addFiles((event.currentTarget as HTMLInputElement).files)}
	/>
	<button
		type="button"
		class="conversation-attachments__trigger"
		aria-label="Attach files"
		title="Attach files"
		{disabled}
		onclick={() => fileInputEl?.click()}
	>
		<span aria-hidden="true">{@html paperclipIcon}</span>
	</button>
	{#if rejectionError}
		<p class="conversation-attachments__error" role="alert">{rejectionError}</p>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
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

		&__trigger {
			display: inline-flex;
			box-sizing: border-box;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			width: var(--space-larger);
			height: var(--space-larger);
			border: var(--border-base) solid transparent;
			border-radius: var(--radius-base);
			color: var(--color-interactive--subtle);
			background: transparent;
			cursor: pointer;
			transition: all var(--timing-base) ease-out;

			:global(svg) {
				display: block;
				width: 20px;
				height: 20px;
			}

			&:hover:not(:disabled),
			&:focus-visible:not(:disabled) {
				color: var(--color-interactive--subtle--hover);
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			&:disabled {
				color: var(--color-disabled);
				cursor: not-allowed;
			}
		}

		&__chip {
			display: inline-flex;
			max-width: 220px;
			align-items: center;
			gap: var(--space-smaller);
			padding: var(--space-smaller) var(--space-small);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface--background);
			font-size: var(--typography--fontSize-smaller);

			&--error {
				border-color: var(--color-critical);
			}
		}

		&__chip-icon {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			color: var(--color-icon);

			:global(svg) {
				display: block;
				width: 14px;
				height: 14px;
			}
		}

		&__chip-name {
			overflow: hidden;
			flex: 0 1 auto;
			color: var(--color-heading);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__chip-meta {
			flex: 0 0 auto;
			color: var(--color-text--secondary);
			white-space: nowrap;
		}

		&__chip--error &__chip-meta {
			color: var(--color-critical);
		}

		&__chip-remove {
			display: grid;
			width: 16px;
			height: 16px;
			flex: 0 0 auto;
			place-items: center;
			border: 0;
			border-radius: var(--radius-circle);
			color: var(--color-icon--secondary);
			background: transparent;
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

			&:disabled {
				cursor: not-allowed;
			}
		}

		&__error {
			flex-basis: 100%;
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
