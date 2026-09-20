<script lang="ts">
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import AsyncMultiPicker from './AsyncMultiPicker.svelte';
	import InsertVariableMenu from './InsertVariableMenu.svelte';
	import { searchCatalogItemsForRule, type RuleLabel } from '$lib/marketing/api';
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
		onRemove
	}: {
		block: MarketingBlock;
		index: number;
		count: number;
		/** Names for catalog item ids a reopened draft's service_summary block already holds. */
		catalogLabels?: RuleLabel[];
		onMove: (by: number) => void;
		onRemove: () => void;
	} = $props();

	const catalogLabelById = $derived(new Map(catalogLabels.map((item) => [item.id, item])));
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
			<Input
				id={`block-${block.id}-url`}
				label="Image link"
				bind:value={block.url}
				placeholder="https://example.com/photo.jpg"
			/>
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
