<script lang="ts">
	import { tick } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import FormErrorSummary from '$lib/components/forms/FormErrorSummary.svelte';
	import SetupStepCard from '$lib/components/layout/SetupStepCard.svelte';
	import CampaignBlockEditor from './CampaignBlockEditor.svelte';
	import CampaignEmailPreview from './CampaignEmailPreview.svelte';
	import VariableField from './VariableField.svelte';
	import { BLOCK_TYPE_ICONS, BLOCK_TYPE_HINTS } from './block-types';
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
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';

	// Step 3 (blueprint §8 step 3): the message itself. `content` is the journey's own $state object -- every
	// field here mutates it in place; only block add/move/remove are owned by the journey (see
	// CampaignJourney's comment on why array-shaped edits are hoisted, mirroring FormSectionEditor).
	// The look is the design skill's `layout.md` → New campaign · Email step: the editor on the left, the
	// live email on the right, one block open at a time.
	let {
		content,
		campaignName,
		errorMessage = '',
		catalogLabels = [],
		onAddBlock,
		onMoveBlock,
		onRemoveBlock,
		onUploadImage,
		onDiscardOrphanedImage,
		onBack,
		onContinue
	}: {
		content: MarketingCampaignContent;
		campaignName: string;
		errorMessage?: string;
		catalogLabels?: RuleLabel[];
		/** Adds the block and hands back its id, so the step can open it. */
		onAddBlock: (type: MarketingBlockType) => string;
		onMoveBlock: (index: number, by: number) => void;
		onRemoveBlock: (index: number) => void;
		/** Uploads a photo for an image block, creating the draft first if this is its very first upload. */
		onUploadImage: (file: File) => Promise<string>;
		onDiscardOrphanedImage: (fileId: string) => void;
		onBack: () => void;
		onContinue: () => void;
	} = $props();

	let openBlockId = $state<string | null>(null);
	let addBlockArea = $state<HTMLDivElement>();
	let formError = $state<{ reveal: () => Promise<void> }>();

	const openBlock = $derived(content.blocks.find((block) => block.id === openBlockId) ?? null);
	const editingBlock = $derived(openBlock ? { id: openBlock.id, type: openBlock.type } : null);
	const canAddBlock = $derived(content.blocks.length < MARKETING_MAX_BLOCKS);

	const addBlockItems = MARKETING_BLOCK_TYPES.map((type) => ({
		label: MARKETING_BLOCK_TYPE_LABELS[type],
		icon: BLOCK_TYPE_ICONS[type],
		tile: 'growth',
		tileSize: 32 as const,
		hint: BLOCK_TYPE_HINTS[type],
		onSelect: () => (openBlockId = justAdded = onAddBlock(type))
	}));

	// A block just added opens with focus in its first place to type (or on Add a photo), not back on Add a
	// block.
	let justAdded: string | null = null;
	function focusAddedBlock(event: Event) {
		const id = justAdded;
		justAdded = null;
		if (!id) return;
		event.preventDefault();
		tick().then(() => {
			const card = document.querySelector<HTMLElement>(`[data-block-id="${id}"]`);
			const target =
				card?.querySelector<HTMLElement>(
					'.block-card__body :is([contenteditable="true"], input:not([type="hidden"]):not([type="file"]), textarea, .photo-slot__add)'
				) ?? card?.querySelector<HTMLElement>('.block-card__title');
			target?.focus();
		});
	}

	function toggleBlock(id: string) {
		openBlockId = openBlockId === id ? null : id;
	}
	// Moving a block re-places its card, which drops keyboard focus; it goes back to the same move button, or
	// to the other one once the block reaches the top or the bottom.
	function moveBlock(index: number, by: number, id: string) {
		onMoveBlock(index, by);
		tick().then(() => {
			const buttons = document.querySelectorAll<HTMLButtonElement>(
				`[data-block-id="${id}"] .block-card__moves button`
			);
			const [up, down] = buttons;
			const wanted = by < 0 ? up : down;
			(wanted && !wanted.disabled ? wanted : by < 0 ? down : up)?.focus();
		});
	}
	// A removed block takes keyboard focus with it, so focus goes to the block now in its place (or the one
	// above), or to Add a block once none are left.
	function removeBlock(index: number) {
		if (content.blocks[index]?.id === openBlockId) openBlockId = null;
		onRemoveBlock(index);
		tick().then(() => {
			const rows = document.querySelectorAll<HTMLElement>(
				'.blocks__list .block-row__button, .blocks__list .block-card__title'
			);
			const target = rows[Math.min(index, rows.length - 1)] ?? addBlockArea?.querySelector('button');
			target?.focus();
		});
	}

	// A failed save names its reason at the top of the editor, and brings it into view.
	$effect(() => {
		if (errorMessage) void formError?.reveal();
	});
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SetupStepCard
	title="Write your email"
	hint="Change it on the left; the right shows exactly what customers get."
	icon={mailIcon}
	tone="growth"
	flush
>
	<div class="email-split">
		<div class="email-split__editor">
			<FormErrorSummary
				bind:this={formError}
				message={errorMessage ? "This email wasn't saved" : ''}
				hint={errorMessage}
			/>

			<VariableField
				id="campaign-subject"
				label="Subject line"
				bind:value={content.subject}
				maxlength={MARKETING_SUBJECT_MAX}
				placeholder="e.g. We miss you!"
			/>
			<VariableField
				id="campaign-preview-text"
				label="Preview text (optional)"
				bind:value={content.preview_text}
				maxlength={MARKETING_PREVIEW_TEXT_MAX}
				placeholder="The line customers see next to the subject"
			/>

			<section class="blocks" aria-labelledby="campaign-blocks-title">
				<div class="blocks__head">
					<h3 id="campaign-blocks-title">Blocks</h3>
					<span>{content.blocks.length} of {MARKETING_MAX_BLOCKS}</span>
				</div>

				{#if content.blocks.length === 0}
					<div class="blocks__empty">
						<b>No blocks yet</b>
						<span>Add a heading, some text and a button to start.</span>
					</div>
				{:else}
					<ol class="blocks__list">
						{#each content.blocks as block, i (block.id)}
							<CampaignBlockEditor
								{block}
								index={i}
								count={content.blocks.length}
								open={block.id === openBlockId}
								{catalogLabels}
								onToggle={() => toggleBlock(block.id)}
								onMove={(by) => moveBlock(i, by, block.id)}
								onRemove={() => removeBlock(i)}
								{onUploadImage}
								{onDiscardOrphanedImage}
							/>
						{/each}
					</ol>
				{/if}

				<div class="blocks__add" bind:this={addBlockArea}>
					<DropdownMenu
						items={addBlockItems}
						triggerLabel="Add a block"
						triggerText="Add a block"
						triggerLeadingIcon={plusIcon}
						triggerChevron={false}
						roomy
						contentClass="email-step__add-menu"
						align="start"
						disabled={!canAddBlock}
						onCloseAutoFocus={focusAddedBlock}
					/>
				</div>
				{#if !canAddBlock}
					<p class="blocks__limit">You've reached the {MARKETING_MAX_BLOCKS}-block limit.</p>
				{/if}
			</section>
		</div>

		<CampaignEmailPreview {content} title={campaignName || 'Preview'} {editingBlock} />
	</div>

	{#snippet footer()}
		<Button variant="secondary" onclick={onBack}>
			<span class="btn-icon" aria-hidden="true">{@html arrowLeftIcon}</span> Back
		</Button>
		<span class="foot-hint">Variables fill in with each customer's own details.</span>
		<Button variant="primary" onclick={onContinue}>
			Continue <span class="btn-icon" aria-hidden="true">{@html arrowRightIcon}</span>
		</Button>
	{/snippet}
</SetupStepCard>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// The step's body is two panes of the same height: the editor (440) and the live email beside it.
	.email-split {
		display: grid;
		grid-template-columns: 440px minmax(0, 1fr);

		&__editor {
			display: flex;
			flex-direction: column;
			gap: var(--space-medium);
			min-width: 0;
			padding: var(--space-medium);
			border-right: var(--border-base) solid var(--color-border);
		}
	}

	.blocks {
		display: flex;
		flex-direction: column;
		gap: 12px;
		// A hairline sets the blocks apart from the two fields above.
		padding-top: var(--space-medium);
		border-top: var(--border-base) solid var(--color-border);

		&__head {
			display: flex;
			align-items: baseline;
			justify-content: space-between;

			h3 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
				font-weight: 600;
			}
			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				font-weight: 500;
			}
		}

		&__list {
			display: flex;
			flex-direction: column;
			gap: 6px;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__empty {
			display: flex;
			flex-direction: column;
			align-items: center;
			gap: 2px;
			padding: var(--space-large) var(--space-medium);
			border-radius: var(--radius-large);
			background: var(--color-surface--background--subtle);
			text-align: center;

			b {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}
			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
			}
		}

		// The Add a block button spans the editor.
		&__add :global(.button) {
			width: 100%;
		}

		&__limit {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	// The menu is as wide as the button it opens from.
	:global(.email-step__add-menu) {
		width: var(--bits-dropdown-menu-anchor-width);
	}

	.foot-hint {
		flex: 1;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: right;
	}

	.btn-icon {
		display: inline-flex;

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}

	// A narrow window puts the email under the editor.
	@media (max-width: 960px) {
		.email-split {
			grid-template-columns: minmax(0, 1fr);

			&__editor {
				border-right: 0;
				border-bottom: var(--border-base) solid var(--color-border);
			}
		}
	}
</style>
