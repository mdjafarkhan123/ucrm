<script lang="ts">
	import Input from '$lib/components/ui/Input.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import InsertVariableMenu from './InsertVariableMenu.svelte';
	import CampaignBlockEditor from './CampaignBlockEditor.svelte';
	import MarketingTemplatePreviewDialog from './MarketingTemplatePreviewDialog.svelte';
	import {
		MARKETING_BLOCK_TYPES,
		MARKETING_BLOCK_TYPE_LABELS,
		MARKETING_MAX_BLOCKS,
		MARKETING_SUBJECT_MAX,
		MARKETING_PREVIEW_TEXT_MAX,
		type MarketingBlockType,
		type MarketingCampaignContent
	} from '$lib/marketing/campaign-content';
	import type { RuleLabel } from '$lib/marketing/api';
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';

	// Step 3 (blueprint §8 step 3): the message itself. `content` is the journey's own $state object -- every
	// field here mutates it in place; only block add/move/remove are owned by the journey (see
	// CampaignJourney's comment on why array-shaped edits are hoisted, mirroring FormSectionEditor).
	let {
		content,
		campaignName,
		errorMessage = '',
		catalogLabels = [],
		onAddBlock,
		onMoveBlock,
		onRemoveBlock,
		onBack,
		onContinue
	}: {
		content: MarketingCampaignContent;
		campaignName: string;
		errorMessage?: string;
		catalogLabels?: RuleLabel[];
		onAddBlock: (type: MarketingBlockType) => void;
		onMoveBlock: (index: number, by: number) => void;
		onRemoveBlock: (index: number) => void;
		onBack: () => void;
		onContinue: () => void;
	} = $props();

	let showPreview = $state(false);

	const addBlockItems = MARKETING_BLOCK_TYPES.map((type) => ({
		label: MARKETING_BLOCK_TYPE_LABELS[type],
		onSelect: () => onAddBlock(type)
	}));
	const canAddBlock = $derived(content.blocks.length < MARKETING_MAX_BLOCKS);

	function insertIntoSubject(token: string) {
		content.subject = content.subject ? `${content.subject} ${token}` : token;
	}
	function insertIntoPreview(token: string) {
		const current = content.preview_text ?? '';
		content.preview_text = current ? `${current} ${token}` : token;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="panel">
	<header class="panel__head">
		<h2>Write your email</h2>
		<p>
			Add blocks to build the message. Variables fill in with each customer's own details when it
			sends.
		</p>
	</header>

	<div class="panel__body">
		{#if errorMessage}
			<p class="panel__error" role="alert">{errorMessage}</p>
		{/if}

		<div class="field-row">
			<Input
				id="campaign-subject"
				label="Subject line"
				bind:value={content.subject}
				maxlength={MARKETING_SUBJECT_MAX}
				placeholder="e.g. We miss you!"
			/>
			<InsertVariableMenu onInsert={insertIntoSubject} />
		</div>

		<div class="field-row">
			<Input
				id="campaign-preview-text"
				label="Preview text (optional)"
				bind:value={content.preview_text}
				maxlength={MARKETING_PREVIEW_TEXT_MAX}
				placeholder="The line customers see next to the subject in their inbox"
			/>
			<InsertVariableMenu onInsert={insertIntoPreview} />
		</div>

		<div class="blocks">
			{#if content.blocks.length === 0}
				<p class="panel__hint">No blocks yet. Add one below to start building the message.</p>
			{:else}
				<ol class="blocks__list">
					{#each content.blocks as block, i (block.id)}
						<CampaignBlockEditor
							{block}
							index={i}
							count={content.blocks.length}
							{catalogLabels}
							onMove={(by) => onMoveBlock(i, by)}
							onRemove={() => onRemoveBlock(i)}
						/>
					{/each}
				</ol>
			{/if}

			<DropdownMenu
				items={addBlockItems}
				triggerLabel="Add a block"
				triggerClass="email-step__add-trigger"
				align="start"
				disabled={!canAddBlock}
			>
				{#snippet trigger()}
					<span class="email-step__button-icon" aria-hidden="true">{@html plusIcon}</span>
					Add a block
				{/snippet}
			</DropdownMenu>
			{#if !canAddBlock}
				<p class="panel__hint">You've reached the {MARKETING_MAX_BLOCKS}-block limit.</p>
			{/if}
		</div>

		<Button variant="secondary" variation="subtle" onclick={() => (showPreview = true)}>
			<span class="email-step__button-icon" aria-hidden="true">{@html eyeIcon}</span>
			Preview email
		</Button>
	</div>

	<footer class="panel__foot">
		<Button variant="secondary" variation="subtle" onclick={onBack}>
			<span class="btn-icon" aria-hidden="true">{@html arrowLeftIcon}</span> Back
		</Button>
		<Button variant="primary" onclick={onContinue}>
			Continue <span class="btn-icon" aria-hidden="true">{@html arrowRightIcon}</span>
		</Button>
	</footer>
</section>

{#if showPreview}
	<MarketingTemplatePreviewDialog
		title={campaignName || 'Preview'}
		{content}
		onClose={() => (showPreview = false)}
	/>
{/if}

<style lang="scss">
	.panel {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		box-shadow: var(--shadow-base);
		overflow: hidden;

		&__head {
			padding: var(--space-large) var(--space-large) var(--space-base);
			border-bottom: 1px solid var(--color-border);

			h2 {
				font-family: var(--typography--fontFamily-display);
				font-size: var(--typography--fontSize-larger);
				font-weight: 600;
				color: var(--color-heading);
				margin: 0;
			}
			p {
				margin: var(--space-smaller) 0 0;
				color: var(--color-text--secondary);
			}
		}

		&__body {
			display: flex;
			flex-direction: column;
			gap: var(--space-large);
			padding: var(--space-large);
		}

		&__error {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__foot {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-slim);
			padding: var(--space-base) var(--space-large);
			border-top: 1px solid var(--color-border);
			background: var(--color-surface--background--subtle);
		}
	}

	.field-row {
		display: flex;
		align-items: flex-end;
		gap: var(--space-small);

		:global(.input) {
			flex: 1;
		}
	}

	.blocks {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}
	}

	.email-step__button-icon {
		display: inline-grid;
		place-items: center;

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.btn-icon :global(svg) {
		width: 16px;
		height: 16px;
		display: block;
	}

	:global(.email-step__add-trigger) {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		align-self: flex-start;
		height: 36px;
		padding: 0 var(--space-base);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		color: var(--color-interactive);
		background: var(--color-surface);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		cursor: pointer;
		transition: all var(--timing-quick) ease-out;
	}
	:global(.email-step__add-trigger:hover:not(:disabled)) {
		background: var(--color-interactive--background--subtle--hover);
	}
	:global(.email-step__add-trigger:focus-visible) {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	:global(.email-step__add-trigger:disabled) {
		color: var(--color-disabled);
		border-color: var(--color-border);
		cursor: not-allowed;
	}

	@media (max-width: 560px) {
		.panel__foot {
			flex-direction: column-reverse;
			align-items: stretch;
		}
		.field-row {
			flex-direction: column;
			align-items: stretch;
		}
	}
</style>
