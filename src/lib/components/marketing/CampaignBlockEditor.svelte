<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import PhotoSlot from '$lib/components/files/PhotoSlot.svelte';
	import AsyncMultiPicker from './AsyncMultiPicker.svelte';
	import VariableField from './VariableField.svelte';
	import { BLOCK_TYPE_ICONS, BLOCK_TYPE_HINTS } from './block-types';
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
		MARKETING_VARIABLE_TAG_LABELS,
		splitMarketingVariables,
		type MarketingBlock
	} from '$lib/marketing/campaign-content';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import arrowUpIcon from '@tabler/icons/outline/arrow-up.svg?raw';
	import arrowDownIcon from '@tabler/icons/outline/arrow-down.svg?raw';
	import alertCircleIcon from '@tabler/icons/outline/exclamation-circle.svg?raw';

	// One block in the email (blueprint §8 step 3), drawn as the design skill's `layout.md` → New campaign ·
	// Email step says: a quiet row that opens when pressed, and the open block as a white card with its
	// fields. Field edits mutate `block` in place -- a plain, non-$bindable prop into the journey's own $state
	// tree, the same direct-mutation convention FormQuestionEditor uses for its question. Add/move/remove
	// stay owned by the journey and arrive here as callbacks, so every array-shaped edit in the builder goes
	// through one consistent path. Which block is open belongs to the step (one at a time).
	let {
		block,
		index,
		count,
		open,
		catalogLabels = [],
		onToggle,
		onMove,
		onRemove,
		onUploadImage,
		onDiscardOrphanedImage
	}: {
		block: MarketingBlock;
		index: number;
		count: number;
		open: boolean;
		/** Names for catalog item ids a reopened draft's service_summary block already holds. */
		catalogLabels?: RuleLabel[];
		onToggle: () => void;
		onMove: (by: number) => void;
		onRemove: () => void;
		/** An image block's own photo box; unused by every other block type. */
		onUploadImage?: (file: File) => Promise<string>;
		onDiscardOrphanedImage?: (fileId: string) => void;
	} = $props();

	const catalogLabelById = $derived(new Map(catalogLabels.map((item) => [item.id, item])));
	const typeLabel = $derived(MARKETING_BLOCK_TYPE_LABELS[block.type]);
	const icon = $derived(BLOCK_TYPE_ICONS[block.type]);

	// A short line saying what the block holds, for its closed row. A variable reads as its tag's words.
	function plain(text: string): string {
		return splitMarketingVariables(text)
			.map((part) =>
				part.kind === 'variable' ? MARKETING_VARIABLE_TAG_LABELS[part.variable] : part.text
			)
			.join('')
			.replace(/\s+/g, ' ')
			.trim();
	}
	const summary = $derived.by(() => {
		switch (block.type) {
			case 'heading':
			case 'text':
				return plain(block.text) || 'Nothing written yet';
			case 'button':
				return plain(block.label) || 'No label yet';
			case 'image':
				return block.alt.trim() || (block.file_id ? 'Photo added' : 'No photo yet');
			case 'divider':
				return BLOCK_TYPE_HINTS.divider;
			case 'service_summary':
				return block.title.trim() || 'No title yet';
		}
	});

	// --- Image block's photo box ------------------------------------------------------------------------

	let imageUploading = $state(false);
	let imageError = $state('');
	// A block loaded from a saved draft already cleared its scan; a block uploaded just now has not yet --
	// the same optimistic-then-never-repolled state ProductsAndServicesBlock's own line photo uses.
	let imageProcessingState = $state<'available' | 'pending'>('available');

	async function handleImageChosen(chosen: File) {
		if (!onUploadImage || block.type !== 'image') return;

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
		imageError = '';
		if (previousFileId) onDiscardOrphanedImage?.(previousFileId);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if !open}
	<li class="block-row">
		<button
			type="button"
			class="block-row__button"
			aria-expanded="false"
			aria-label={`Edit block ${index + 1}, ${typeLabel}`}
			onclick={onToggle}
		>
			<IconTile {icon} tone="growth" size={32} />
			<span class="block-row__type">{typeLabel}</span>
			<span class="block-row__summary">{summary}</span>
		</button>
	</li>
{:else}
	<li class="block-card" data-block-id={block.id}>
		<header class="block-card__head">
			<button
				type="button"
				class="block-card__title"
				aria-expanded="true"
				aria-label={`Close block ${index + 1}, ${typeLabel}`}
				onclick={onToggle}
			>
				<span class="block-card__tile" aria-hidden="true">{@html icon}</span>
				<span class="block-card__type">{typeLabel}</span>
			</button>
			<div class="block-card__moves" role="group" aria-label={`Move block ${index + 1}`}>
				<Button
					variant="secondary"
					size="small"
					iconOnly
					label={`Move block ${index + 1} up`}
					disabled={index === 0}
					onclick={() => onMove(-1)}
				>
					{@html arrowUpIcon}
				</Button>
				<Button
					variant="secondary"
					size="small"
					iconOnly
					label={`Move block ${index + 1} down`}
					disabled={index === count - 1}
					onclick={() => onMove(1)}
				>
					{@html arrowDownIcon}
				</Button>
			</div>
			<Button
				variant="secondary"
				size="small"
				variation="destructive"
				iconOnly
				label={`Remove block ${index + 1}`}
				onclick={onRemove}
			>
				{@html trashIcon}
			</Button>
		</header>

		<div class="block-card__body">
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
				<VariableField
					id={`block-${block.id}-text`}
					label="Heading text"
					bind:value={block.text}
					maxlength={MARKETING_HEADING_TEXT_MAX}
				/>
			{:else if block.type === 'text'}
				<VariableField
					id={`block-${block.id}-text`}
					label="Text"
					hideLabel
					multiline
					bind:value={block.text}
					maxlength={MARKETING_TEXT_BLOCK_MAX}
				/>
			{:else if block.type === 'button'}
				<VariableField
					id={`block-${block.id}-label`}
					label="Button label"
					bind:value={block.label}
					maxlength={MARKETING_BUTTON_LABEL_MAX}
				/>
				<Input
					id={`block-${block.id}-url`}
					label="Link"
					bind:value={block.url}
					placeholder="https://example.com"
				/>
			{:else if block.type === 'image'}
				<div class="block-card__photo">
					<PhotoSlot
						fileId={block.file_id || null}
						processingState={imageProcessingState}
						uploading={imageUploading}
						label="Campaign image"
						addText="Add a photo"
						onChoose={(file) => void handleImageChosen(file)}
						onRemove={removeImage}
					/>
				</div>
				{#if imageError}
					<p class="block-card__error" role="alert">
						<span aria-hidden="true">{@html alertCircleIcon}</span>{imageError}
					</p>
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
				<p class="block-card__hint">A horizontal line to separate sections.</p>
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
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// A closed block: the whole row presses open.
	.block-row {
		list-style: none;

		&__button {
			display: flex;
			align-items: center;
			gap: 10px;
			width: 100%;
			padding: 8px 12px 8px 8px;
			border: var(--border-base) solid var(--color-border);
			border-radius: 10px;
			background: var(--color-surface--background--subtle);
			color: inherit;
			font: inherit;
			text-align: left;
			cursor: pointer;
			transition: border-color var(--timing-quick) ease-out;

			&:hover {
				border-color: var(--color-border--interactive--hover);
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__type {
			flex: none;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__summary {
			flex: 1;
			min-width: 0;
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			text-overflow: ellipsis;
			white-space: nowrap;
		}
	}

	// The open block: white, edged in the Marketing colour, its fields under the head.
	.block-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);
		padding: 8px 8px 12px;
		border: 1.5px solid var(--color-growth);
		border-radius: 10px;
		background: var(--color-surface);
		list-style: none;

		&__head {
			display: flex;
			align-items: center;
			gap: 6px;
		}

		&__title {
			display: flex;
			flex: 1;
			min-width: 0;
			align-items: center;
			gap: 10px;
			padding: 0;
			border: 0;
			border-radius: var(--radius-base);
			background: none;
			font: inherit;
			text-align: left;
			cursor: pointer;

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		// The filled tile marks the block being edited.
		&__tile {
			display: grid;
			flex: none;
			place-items: center;
			width: 32px;
			height: 32px;
			border-radius: var(--radius-base);
			color: var(--color-text--reverse);
			background: var(--color-growth);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__type {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 700;
		}

		// Move up / Move down: one box with the soft grey edge, as the calendar's stepper is.
		&__moves {
			display: inline-flex;
			--button--edge: var(--color-border--interactive);
			--button--edge--hover: var(--color-border--interactive--hover);

			:global(.button) {
				border-radius: 0;
			}
			:global(.button:first-child) {
				border-radius: var(--radius-base) 0 0 var(--radius-base);
			}
			:global(.button:last-child) {
				border-radius: 0 var(--radius-base) var(--radius-base) 0;
			}
			:global(.button + .button) {
				margin-left: -1px;
			}
			:global(.button:focus-visible) {
				z-index: 1;
			}
			:global(.button:disabled) {
				color: var(--color-disabled);
			}
		}

		&__body {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);
			padding-inline: 4px;
		}

		&__photo {
			height: 160px;
		}

		&__error {
			display: flex;
			align-items: flex-start;
			gap: 6px;
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
			line-height: 1.4;

			span {
				display: inline-flex;
				flex: none;
			}
			span :global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
