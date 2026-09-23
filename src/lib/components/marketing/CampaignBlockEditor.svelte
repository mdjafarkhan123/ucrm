<script lang="ts">
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import FileThumb from '$lib/components/files/FileThumb.svelte';
	import AsyncMultiPicker from './AsyncMultiPicker.svelte';
	import InsertVariableMenu from './InsertVariableMenu.svelte';
	import { searchCatalogItemsForRule, type RuleLabel } from '$lib/marketing/api';
	import { MAX_ATTACHMENT_SIZE_BYTES } from '$lib/collaboration/attachment-limits';
	import {
		MARKETING_BLOCK_TYPE_LABELS,
		MARKETING_HEADING_TEXT_MAX,
		MARKETING_TEXT_BLOCK_MAX,
		MARKETING_BUTTON_LABEL_MAX,
		MARKETING_IMAGE_ALT_MAX,
		MARKETING_SERVICE_SUMMARY_TITLE_MAX,
		MARKETING_SERVICE_SUMMARY_MAX_ITEMS,
		type MarketingBlock
	} from '$lib/marketing/campaign-content';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import arrowUpIcon from '@tabler/icons/outline/arrow-up.svg?raw';
	import arrowDownIcon from '@tabler/icons/outline/arrow-down.svg?raw';
	import uploadIcon from '@tabler/icons/outline/upload.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';

	// One block in the email (blueprint §8 step 3). Field edits mutate `block` in place -- a plain,
	// non-$bindable prop into the journey's own $state tree, the same direct-mutation convention
	// FormQuestionEditor uses for its question. Add/move/remove stay owned by the journey and arrive here as
	// callbacks, so every array-shaped edit in the builder goes through one consistent path.
	let {
		block,
		index,
		count,
		catalogLabels = [],
		onMove,
		onRemove,
		onUploadImage,
		onDiscardOrphanedImage
	}: {
		block: MarketingBlock;
		index: number;
		count: number;
		/** Names for catalog item ids a reopened draft's service_summary block already holds. */
		catalogLabels?: RuleLabel[];
		onMove: (by: number) => void;
		onRemove: () => void;
		/** An image block's own photo well; unused by every other block type. */
		onUploadImage?: (file: File) => Promise<string>;
		onDiscardOrphanedImage?: (fileId: string) => void;
	} = $props();

	const catalogLabelById = $derived(new Map(catalogLabels.map((item) => [item.id, item])));

	// --- Image block's photo well -------------------------------------------------------------------------

	let imageInputEl: HTMLInputElement | undefined = $state();
	let imageUploading = $state(false);
	let imageError = $state('');
	// A block loaded from a saved draft already cleared its scan; a block uploaded just now has not yet --
	// the same optimistic-then-never-repolled state ProductsAndServicesBlock's own line photo uses.
	let imageProcessingState = $state<'available' | 'pending'>('available');

	function openImagePicker() {
		imageInputEl?.click();
	}

	async function handleImageChosen(fileList: FileList | null) {
		const chosen = fileList?.[0];
		if (imageInputEl) imageInputEl.value = '';
		if (!chosen || !onUploadImage || block.type !== 'image') return;

		if (!chosen.type.startsWith('image/')) {
			imageError = 'Only a photo can be used for an image block.';
			return;
		}
		if (chosen.size > MAX_ATTACHMENT_SIZE_BYTES) {
			imageError = 'That photo is over 25 MB.';
			return;
		}

		const previousFileId = block.file_id;
		imageUploading = true;
		imageError = '';
		try {
			block.file_id = await onUploadImage(chosen);
			imageProcessingState = 'pending';
			if (previousFileId) onDiscardOrphanedImage?.(previousFileId);
		} catch (caught) {
			imageError = caught instanceof Error ? caught.message : 'That photo could not be uploaded.';
		} finally {
			imageUploading = false;
		}
	}

	function removeImage() {
		if (block.type !== 'image') return;
		const previousFileId = block.file_id;
		block.file_id = '';
		if (previousFileId) onDiscardOrphanedImage?.(previousFileId);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<li class="block-editor">
	<header class="block-editor__head">
		<span class="block-editor__type">{MARKETING_BLOCK_TYPE_LABELS[block.type]}</span>
		<div class="block-editor__actions">
			<button
				type="button"
				class="block-editor__icon-button"
				aria-label={`Move block ${index + 1} up`}
				disabled={index === 0}
				onclick={() => onMove(-1)}
			>
				{@html arrowUpIcon}
			</button>
			<button
				type="button"
				class="block-editor__icon-button"
				aria-label={`Move block ${index + 1} down`}
				disabled={index === count - 1}
				onclick={() => onMove(1)}
			>
				{@html arrowDownIcon}
			</button>
			<button
				type="button"
				class="block-editor__icon-button block-editor__icon-button--danger"
				aria-label={`Remove block ${index + 1}`}
				onclick={onRemove}
			>
				{@html trashIcon}
			</button>
		</div>
	</header>

	<div class="block-editor__body">
		{#if block.type === 'heading'}
			<Select
				id={`block-${block.id}-level`}
				label="Heading size"
				value={block.level}
				options={[
					{ value: 'h1', label: 'Large' },
					{ value: 'h2', label: 'Standard' }
				]}
				onchange={(value) => (block.level = value as 'h1' | 'h2')}
			/>
			<div class="field-row">
				<Input
					id={`block-${block.id}-text`}
					label="Heading text"
					bind:value={block.text}
					maxlength={MARKETING_HEADING_TEXT_MAX}
				/>
				<InsertVariableMenu
					onInsert={(token) => (block.text = block.text ? `${block.text} ${token}` : token)}
				/>
			</div>
		{:else if block.type === 'text'}
			<div class="field-row field-row--top">
				<Textarea
					id={`block-${block.id}-text`}
					label="Text"
					bind:value={block.text}
					rows={4}
					maxlength={MARKETING_TEXT_BLOCK_MAX}
				/>
				<InsertVariableMenu
					onInsert={(token) => (block.text = block.text ? `${block.text} ${token}` : token)}
				/>
			</div>
		{:else if block.type === 'button'}
			<div class="field-row">
				<Input
					id={`block-${block.id}-label`}
					label="Button label"
					bind:value={block.label}
					maxlength={MARKETING_BUTTON_LABEL_MAX}
				/>
				<InsertVariableMenu
					onInsert={(token) => (block.label = block.label ? `${block.label} ${token}` : token)}
				/>
			</div>
			<Input
				id={`block-${block.id}-url`}
				label="Link"
				bind:value={block.url}
				placeholder="https://example.com"
			/>
		{:else if block.type === 'image'}
			<div class="image-well" class:image-well--filled={Boolean(block.file_id)}>
				<input
					bind:this={imageInputEl}
					type="file"
					accept="image/*"
					class="image-well__file-input"
					tabindex={-1}
					aria-hidden="true"
					onchange={(event) =>
						void handleImageChosen((event.currentTarget as HTMLInputElement).files)}
				/>
				{#if imageUploading}
					<span class="image-well__loading" aria-hidden="true"></span>
				{:else if block.file_id}
					<FileThumb
						fileId={block.file_id}
						displayName={block.alt || 'Campaign image'}
						mimeType="image/jpeg"
						kind="image"
						processingState={imageProcessingState}
						hasThumbnail={false}
						size="panel"
					/>
					<div class="image-well__tools">
						<button
							type="button"
							class="image-well__tool"
							aria-label="Replace photo"
							onclick={openImagePicker}
						>
							{@html pencilIcon}
						</button>
						<button
							type="button"
							class="image-well__tool image-well__tool--danger"
							aria-label="Remove photo"
							onclick={removeImage}
						>
							{@html trashIcon}
						</button>
					</div>
				{:else}
					<button type="button" class="image-well__add" onclick={openImagePicker}>
						{@html uploadIcon} Add a photo
					</button>
				{/if}
			</div>
			{#if imageError}
				<p class="image-well__error" role="alert">{imageError}</p>
			{/if}
			<Input
				id={`block-${block.id}-alt`}
				label="Alt text (for accessibility)"
				bind:value={block.alt}
				maxlength={MARKETING_IMAGE_ALT_MAX}
			/>
			<Input
				id={`block-${block.id}-link`}
				label="Link when clicked (optional)"
				value={block.link_url ?? ''}
				oninput={(event: Event & { currentTarget: HTMLInputElement }) => {
					const value = event.currentTarget.value;
					block.link_url = value.trim() ? value : undefined;
				}}
				placeholder="https://example.com"
			/>
		{:else if block.type === 'divider'}
			<p class="block-editor__hint">A horizontal line to separate sections.</p>
		{:else if block.type === 'service_summary'}
			<Input
				id={`block-${block.id}-title`}
				label="Title"
				bind:value={block.title}
				maxlength={MARKETING_SERVICE_SUMMARY_TITLE_MAX}
			/>
			<AsyncMultiPicker
				id={`block-${block.id}-services`}
				max={MARKETING_SERVICE_SUMMARY_MAX_ITEMS}
				placeholder="Search the price list"
				queryKey="campaign-service-summary"
				search={searchCatalogItemsForRule}
				ids={block.catalog_item_ids}
				initialItems={block.catalog_item_ids
					.map((itemId) => catalogLabelById.get(itemId))
					.filter((item) => item !== undefined)}
				onChange={(next) => (block.catalog_item_ids = next)}
			/>
		{/if}
	</div>
</li>

<style lang="scss">
	.block-editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		&__head {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__type {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			text-transform: uppercase;
			letter-spacing: 0.04em;
		}

		&__actions {
			display: flex;
			gap: var(--space-smaller);
		}

		&__body {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__icon-button {
			display: grid;
			place-items: center;
			width: 32px;
			height: 32px;
			padding: 0;
			border: var(--border-base) solid transparent;
			border-radius: var(--radius-base);
			color: var(--color-icon--secondary);
			background: none;
			cursor: pointer;
			transition: all var(--timing-quick) ease-out;

			:global(svg) {
				width: 16px;
				height: 16px;
			}

			&:hover:not(:disabled),
			&:focus-visible:not(:disabled) {
				border-color: var(--color-border--interactive);
				color: var(--color-interactive);
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
			&:disabled {
				color: var(--color-disabled);
				cursor: not-allowed;
			}
			&--danger:hover:not(:disabled),
			&--danger:focus-visible:not(:disabled) {
				border-color: var(--color-critical);
				color: var(--color-critical);
			}
		}
	}

	.image-well {
		position: relative;
		width: 100%;
		max-width: 320px;
		aspect-ratio: 4 / 3;
		overflow: hidden;
		border: var(--border-base) dashed var(--color-border--interactive);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);

		&--filled {
			border-style: solid;
		}

		&__file-input {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip: rect(0 0 0 0);
		}

		&__add {
			display: flex;
			width: 100%;
			height: 100%;
			flex-direction: column;
			align-items: center;
			justify-content: center;
			gap: var(--space-smaller);
			border: 0;
			color: var(--color-text--secondary);
			background: none;
			font-size: var(--typography--fontSize-small);
			cursor: pointer;

			:global(svg) {
				width: 22px;
				height: 22px;
			}
			&:hover {
				color: var(--color-interactive);
			}
		}

		&__loading {
			display: block;
			width: 100%;
			height: 100%;
			background: var(--color-surface--hover);
		}

		&__tools {
			position: absolute;
			top: var(--space-smaller);
			right: var(--space-smaller);
			display: flex;
			gap: var(--space-smaller);
		}

		&__tool {
			display: grid;
			width: 28px;
			height: 28px;
			place-items: center;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			color: var(--color-icon--secondary);
			background: var(--color-surface);
			cursor: pointer;

			:global(svg) {
				width: 14px;
				height: 14px;
			}
			&:hover {
				color: var(--color-interactive);
			}
			&--danger:hover {
				color: var(--color-critical);
			}
		}

		&__error {
			margin: 0;
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-smaller);
		}
	}

	.field-row {
		display: flex;
		align-items: flex-end;
		gap: var(--space-small);

		&--top {
			align-items: flex-start;
		}

		:global(.input),
		:global(.textarea) {
			flex: 1;
		}
	}

	@media (max-width: 560px) {
		.field-row {
			flex-direction: column;
			align-items: stretch;
		}
	}
</style>
