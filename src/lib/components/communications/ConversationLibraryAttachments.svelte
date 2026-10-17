<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import { formatFileSize } from '$lib/collaboration/format';
	import { iconForMimeType } from '$lib/collaboration/file-icons';
	import FilePicker from '$lib/components/files/FilePicker.svelte';
	import type { FileListItem } from '$lib/files/api';
	import filesIcon from '@tabler/icons/outline/files.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	// Files and Media Part 6E: the composer's other attach control, next to ConversationAttachments'
	// paperclip. This one never uploads -- it opens the File Manager picker in 'select' mode and hands back
	// Files that are already checked and available, so nothing here duplicates the scan pipeline. The parent
	// resolves the picked ids into a real send-time attachment server-side and clears this list after Send,
	// the same as it clears ConversationAttachments.
	let {
		files,
		onChange,
		disabled = false,
		variant = 'email',
		clientId = null,
		clientLabel = null
	}: {
		files: Pick<FileListItem, 'id' | 'display_name' | 'mime_type' | 'size_bytes'>[];
		onChange: (
			files: Pick<FileListItem, 'id' | 'display_name' | 'mime_type' | 'size_bytes'>[]
		) => void;
		disabled?: boolean;
		variant?: 'email' | 'sms';
		clientId?: string | null;
		clientLabel?: string | null;
	} = $props();

	const isSms = $derived(variant === 'sms');
	const maxFiles = $derived(isSms ? 1 : 10);
	const triggerLabel = $derived(isSms ? 'Attach a file from Files' : 'Attach files from Files');

	let pickerOpen = $state(false);

	function handleSelected(picked: FileListItem[]) {
		const existingIds = new Set(files.map((file) => file.id));
		const additions = picked.filter((file) => !existingIds.has(file.id));
		onChange([...files, ...additions].slice(0, maxFiles));
	}

	function remove(fileId: string) {
		onChange(files.filter((file) => file.id !== fileId));
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="conversation-library-attachments">
	{#each files as file (file.id)}
		<span class="conversation-library-attachments__chip">
			<span class="conversation-library-attachments__chip-icon" aria-hidden="true"
				>{@html iconForMimeType(file.mime_type)}</span
			>
			<span class="conversation-library-attachments__chip-name" title={file.display_name}
				>{file.display_name}</span
			>
			<span class="conversation-library-attachments__chip-meta"
				>{formatFileSize(file.size_bytes)}</span
			>
			<button
				type="button"
				class="conversation-library-attachments__chip-remove"
				aria-label={`Remove ${file.display_name}`}
				{disabled}
				onclick={() => remove(file.id)}
			>
				{@html xIcon}
			</button>
		</span>
	{/each}
	<Button
		variant="secondary"
		size="small"
		iconOnly
		label={triggerLabel}
		disabled={disabled || files.length >= maxFiles}
		onclick={() => (pickerOpen = true)}
	>
		{@html filesIcon}
	</Button>
</div>

<FilePicker
	open={pickerOpen}
	mode="select"
	{clientId}
	{clientLabel}
	onClose={() => (pickerOpen = false)}
	onSelected={handleSelected}
/>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.conversation-library-attachments {
		display: contents;

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
	}
</style>
