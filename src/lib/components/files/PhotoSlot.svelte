<script lang="ts">
	import FileThumb from '$lib/components/files/FileThumb.svelte';
	import type { FileProcessingState } from '$lib/files/api';
	import uploadIcon from '@tabler/icons/outline/upload.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	// One optional photo box: a dashed "add" target when empty, the photo with replace and remove buttons
	// when filled. A quote line and a price list item both hold exactly one photo this way. The box fills
	// its parent, so the caller decides how big it is.
	let {
		previewUrl = '',
		fileId = null,
		processingState = 'available',
		uploading = false,
		disabled = false,
		label = 'Photo',
		onChoose,
		onRemove
	}: {
		/** A local object URL for a photo picked but not uploaded yet. Shown ahead of `fileId`. */
		previewUrl?: string;
		/** A photo already in the File Manager. */
		fileId?: string | null;
		processingState?: FileProcessingState;
		uploading?: boolean;
		disabled?: boolean;
		/** What the photo is of, for its alt text and the buttons' names. */
		label?: string;
		onChoose: (file: File) => void;
		onRemove: () => void;
	} = $props();

	let input = $state<HTMLInputElement>();

	const filled = $derived(Boolean(previewUrl || fileId));

	function handleChange(event: Event) {
		const target = event.currentTarget as HTMLInputElement;
		const chosen = target.files?.[0];
		// Clearing the input lets the same file be picked again after a remove.
		target.value = '';
		if (chosen) onChoose(chosen);
	}

	function openPicker() {
		input?.click();
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="photo-slot" class:photo-slot--filled={filled}>
	<input
		bind:this={input}
		type="file"
		accept="image/*"
		class="photo-slot__input"
		tabindex={-1}
		aria-hidden="true"
		onchange={handleChange}
	/>
	{#if uploading}
		<span class="photo-slot__loading" aria-hidden="true"></span>
	{:else if filled}
		{#if previewUrl}
			<img class="photo-slot__image" src={previewUrl} alt={label} />
		{:else if fileId}
			<FileThumb
				{fileId}
				displayName={label}
				mimeType="image/jpeg"
				kind="image"
				{processingState}
				hasThumbnail={processingState === 'available'}
				size="tile"
			/>
		{/if}
		<!-- Always visible, so nobody has to guess that a saved photo can still be swapped. -->
		<div class="photo-slot__tools">
			<button
				type="button"
				class="photo-slot__tool photo-slot__tool--replace"
				aria-label="Replace photo"
				{disabled}
				onclick={openPicker}
			>
				{@html pencilIcon}
			</button>
			<button
				type="button"
				class="photo-slot__tool photo-slot__tool--remove"
				aria-label="Remove photo"
				{disabled}
				onclick={onRemove}
			>
				{@html trashIcon}
			</button>
		</div>
	{:else}
		<button
			type="button"
			class="photo-slot__add"
			aria-label="Add a photo"
			{disabled}
			onclick={openPicker}
		>
			{@html uploadIcon}
		</button>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.photo-slot {
		position: relative;
		display: grid;
		width: 100%;
		height: 100%;
		min-height: 96px;
		place-items: center;
		overflow: hidden;
		border: var(--border-base) dashed var(--color-border--interactive);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		// Once there is a photo the box stops inviting a drop and just frames what is there.
		&--filled {
			border-style: solid;
			border-color: var(--color-border);
		}

		// FileThumb's own tile sizing is a 4/3 box; here it must fill whatever size the caller gives.
		:global(.file-thumb--tile) {
			width: 100%;
			height: 100%;
			aspect-ratio: auto;
		}

		&__input {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip: rect(0 0 0 0);
			white-space: nowrap;
		}

		&__image {
			display: block;
			width: 100%;
			height: 100%;
			object-fit: cover;
		}

		&__add {
			display: grid;
			width: 100%;
			height: 100%;
			place-items: center;
			border: 0;
			background: transparent;
			color: var(--color-interactive);
			cursor: pointer;

			:global(svg) {
				width: 22px;
				height: 22px;
			}
			&:hover:not(:disabled) {
				color: var(--color-interactive--hover);
				background: var(--color-interactive--background--subtle--hover);
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
			&:disabled {
				cursor: not-allowed;
			}
		}

		&__tools {
			position: absolute;
			top: var(--space-smallest);
			right: var(--space-smallest);
			display: grid;
			gap: var(--space-smallest);
		}

		&__tool {
			display: grid;
			width: 22px;
			height: 22px;
			place-items: center;
			border: 0;
			border-radius: var(--radius-circle);
			background: var(--color-surface);
			box-shadow: var(--shadow-low);
			cursor: pointer;

			:global(svg) {
				width: 14px;
				height: 14px;
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
			&:disabled {
				cursor: not-allowed;
				opacity: 0.6;
			}
			&--replace {
				color: var(--color-interactive);

				&:hover:not(:disabled) {
					color: var(--color-interactive--hover);
				}
			}
			&--remove {
				color: var(--color-critical);

				&:hover:not(:disabled) {
					color: var(--color-critical--onSurface);
				}
			}
		}

		&__loading {
			width: 22px;
			height: 22px;
			border: 2px solid var(--color-border);
			border-top-color: var(--color-interactive);
			border-radius: var(--radius-circle);
			animation: photo-slot-spin 0.8s linear infinite;
		}
	}

	@keyframes photo-slot-spin {
		to {
			transform: rotate(360deg);
		}
	}
</style>
