<script lang="ts" module>
	/** One photo or file on a Note being written: already on the Note, uploading, uploaded, or refused. */
	export type NoteAttachItem = {
		key: string;
		name: string;
		status: 'saved' | 'uploading' | 'uploaded' | 'error';
		progress: number;
		fileId: string | null;
		error: string;
	};

	export const NOTE_FILE_LIMIT = 10;

	/** The ids the Note should hold, in order -- what is on it and what finished uploading. */
	export function attachedFileIds(items: NoteAttachItem[]) {
		return items
			.filter((item) => item.status === 'saved' || item.status === 'uploaded')
			.map((item) => item.fileId)
			.filter((id): id is string => Boolean(id));
	}

	export function isUploading(items: NoteAttachItem[]) {
		return items.some((item) => item.status === 'uploading');
	}
</script>

<script lang="ts">
	import { uploadAttachmentFile } from '$lib/collaboration/api';
	import { finishFileUpload, startFileUpload } from '$lib/files/api';
	import { FILE_PICKER_ACCEPT, MAX_FILE_SIZE_BYTES, allowedTypeFor } from '$lib/files/allowlist';
	import paperclipIcon from '@tabler/icons/outline/paperclip.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	// Adds photos and files to a Brief Note before it is saved. Each upload starts the moment it is picked
	// (on a phone the picker offers the camera too), the same two-step handshake the File Manager uses, and
	// is sent with the Note once it has reached storage. The virus check finishes on its own afterwards; the
	// Note shows "Still being checked" until then. Up to ten per Note.
	let {
		id,
		items = $bindable([]),
		originType,
		originId,
		disabled = false
	}: {
		id: string;
		items?: NoteAttachItem[];
		/** The Request or Client the Note is going on; a Note's file can only land on this card's own. */
		originType: 'request' | 'client';
		originId: string | null;
		disabled?: boolean;
	} = $props();

	let input = $state<HTMLInputElement | null>(null);
	const kept = $derived(items.filter((item) => item.status !== 'error').length);
	const full = $derived(kept >= NOTE_FILE_LIMIT);

	function patch(key: string, changes: Partial<NoteAttachItem>) {
		items = items.map((item) => (item.key === key ? { ...item, ...changes } : item));
	}

	function remove(key: string) {
		items = items.filter((item) => item.key !== key);
	}

	function addFiles(fileList: FileList | null) {
		if (!fileList || !originId) return;
		let room = NOTE_FILE_LIMIT - kept;
		for (const file of Array.from(fileList)) {
			const key = `${file.name}-${file.size}-${Date.now()}-${Math.random()}`;
			const refusal = !allowedTypeFor(file.name)
				? 'That kind of file cannot be added.'
				: file.size > MAX_FILE_SIZE_BYTES
					? 'Files can be up to 100 MB.'
					: file.size === 0
						? 'That file is empty.'
						: room <= 0
							? `A note can hold up to ${NOTE_FILE_LIMIT} photos and files.`
							: '';
			items = [
				...items,
				{
					key,
					name: file.name,
					status: refusal ? 'error' : 'uploading',
					progress: 0,
					fileId: null,
					error: refusal
				}
			];
			if (!refusal) {
				room -= 1;
				void upload(key, file, originId);
			}
		}
	}

	async function upload(key: string, file: File, recordId: string) {
		try {
			const started = await startFileUpload(file, {
				originType,
				originId: recordId,
				originRole: 'note_file'
			});
			let shown = -1;
			await uploadAttachmentFile(started.upload_url, file, (fraction) => {
				const percent = Math.round(fraction * 100);
				if (percent === shown) return;
				shown = percent;
				patch(key, { progress: fraction });
			});
			await finishFileUpload(started.file.id);
			patch(key, { status: 'uploaded', progress: 1, fileId: started.file.id });
		} catch (error) {
			patch(key, {
				status: 'error',
				progress: 0,
				error: error instanceof Error ? error.message : 'That file could not be uploaded.'
			});
		}
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="note-attach">
	{#if items.length > 0}
		<ul class="note-attach__list" aria-label="Photos and files on this note">
			{#each items as item (item.key)}
				<li class="note-attach__item" class:note-attach__item--error={item.status === 'error'}>
					{#if item.status === 'error'}
						<span class="note-attach__icon" aria-hidden="true">{@html alertTriangleIcon}</span>
					{/if}
					<span class="note-attach__text">
						<span class="note-attach__name">{item.name}</span>
						{#if item.status === 'uploading'}
							<span class="note-attach__meta">Uploading {Math.round(item.progress * 100)}%</span>
						{:else if item.status === 'error'}
							<span class="note-attach__meta" role="alert">{item.error}</span>
						{/if}
					</span>
					<button
						type="button"
						class="note-attach__remove"
						aria-label={`Remove ${item.name}`}
						{disabled}
						onclick={() => remove(item.key)}
					>
						<span aria-hidden="true">{@html xIcon}</span>
					</button>
					{#if item.status === 'uploading'}
						<span
							class="note-attach__progress"
							style:width={`${Math.round(item.progress * 100)}%`}
							aria-hidden="true"
						></span>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}

	<input
		bind:this={input}
		{id}
		class="note-attach__input"
		type="file"
		multiple
		accept={FILE_PICKER_ACCEPT}
		tabindex="-1"
		aria-hidden="true"
		onchange={(event) => {
			addFiles(event.currentTarget.files);
			event.currentTarget.value = '';
		}}
	/>
	<button
		type="button"
		class="note-attach__add"
		disabled={disabled || full || !originId}
		title={full ? `A note can hold up to ${NOTE_FILE_LIMIT} photos and files.` : undefined}
		onclick={() => input?.click()}
	>
		<span aria-hidden="true">{@html paperclipIcon}</span>Attach photos or files
	</button>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.note-attach {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-small);

		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			width: 100%;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__item {
			position: relative;
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-smaller) var(--space-small);
			overflow: hidden;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);

			&--error {
				border-color: var(--color-critical);
				background: var(--color-critical--surface);
			}
		}

		&__icon {
			display: grid;
			flex: 0 0 auto;
			color: var(--color-critical);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__text {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			min-width: 0;
		}

		&__name {
			overflow: hidden;
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__meta {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}

		&__item--error &__meta {
			color: var(--color-critical--onSurface);
		}

		&__remove {
			display: grid;
			flex: 0 0 auto;
			width: 28px;
			height: 28px;
			place-items: center;
			padding: 0;
			border: 0;
			border-radius: var(--radius-base);
			color: var(--color-icon--secondary);
			background: transparent;
			cursor: pointer;

			&:hover:not(:disabled) {
				color: var(--color-text);
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: transparent;
				box-shadow: var(--shadow-focus);
			}

			&:disabled {
				cursor: not-allowed;
				opacity: 0.5;
			}

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__progress {
			position: absolute;
			bottom: 0;
			left: 0;
			height: 2px;
			background: var(--color-interactive);
			transition: width 120ms linear;
		}

		&__input {
			display: none;
		}

		&__add {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			padding: var(--space-smaller) var(--space-small);
			border: 0;
			border-radius: var(--radius-base);
			color: var(--color-interactive);
			background: transparent;
			font: inherit;
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			cursor: pointer;

			&:hover:not(:disabled) {
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: transparent;
				box-shadow: var(--shadow-focus);
			}

			&:disabled {
				color: var(--color-text--secondary);
				cursor: not-allowed;
			}

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
	}
</style>
