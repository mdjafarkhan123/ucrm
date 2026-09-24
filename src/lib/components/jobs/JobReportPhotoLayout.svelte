<script lang="ts">
	import { flip } from 'svelte/animate';
	import { dragHandleZone, dragHandle, type DndEvent } from 'svelte-dnd-action';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import FileThumb from '$lib/components/files/FileThumb.svelte';
	import type { JobReportCandidatePhoto } from '$lib/jobs/report-types';
	import {
		addPhotos,
		addSection,
		canMoveItem,
		isEmpty,
		layoutFileIds,
		makePair,
		moveItem,
		moveSection,
		removeItem,
		removeSection,
		splitPair,
		swapPair,
		updateSection,
		type ArrangedItem,
		type ArrangedLayout,
		type ArrangedSection
	} from '$lib/jobs/report-layout';
	import gripIcon from '@tabler/icons/outline/grip-vertical.svg?raw';
	import arrowUpIcon from '@tabler/icons/outline/arrow-up.svg?raw';
	import arrowDownIcon from '@tabler/icons/outline/arrow-down.svg?raw';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';
	import swapIcon from '@tabler/icons/outline/arrows-left-right.svg?raw';
	import pairIcon from '@tabler/icons/outline/link.svg?raw';
	import unpairIcon from '@tabler/icons/outline/unlink.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';

	// Arranging a work report's photos (Part 7C): the order, optional headings with a note, and before/after
	// pairs. Every change goes through `$lib/jobs/report-layout`, which returns a new arrangement; this only
	// draws it and assigns. Nothing is saved until the dialog's own Save.

	let {
		candidates,
		layout = $bindable(),
		invalidSectionIds = [],
		disabled = false
	}: {
		candidates: JobReportCandidatePhoto[];
		layout: ArrangedLayout;
		/** Headings the last save attempt refused for having no name. */
		invalidSectionIds?: string[];
		disabled?: boolean;
	} = $props();

	const FLIP_MS = 150;

	const byId = $derived(new Map(candidates.map((candidate) => [candidate.file_id, candidate])));
	const onReport = $derived(new Set(layoutFileIds(layout)));
	const notOnReport = $derived(candidates.filter((candidate) => !onReport.has(candidate.file_id)));

	// The single photo whose partner is being picked, while the contractor makes a pair.
	let pairingFrom = $state<string | null>(null);

	function setTopItems(event: CustomEvent<DndEvent<ArrangedItem>>) {
		layout = { ...layout, top: event.detail.items };
	}

	function setSectionItems(sectionId: string, event: CustomEvent<DndEvent<ArrangedItem>>) {
		layout = {
			...layout,
			sections: layout.sections.map((section) =>
				section.id === sectionId ? { ...section, items: event.detail.items } : section
			)
		};
	}

	function setSections(event: CustomEvent<DndEvent<ArrangedSection>>) {
		layout = { ...layout, sections: event.detail.items };
	}

	function add(photos: JobReportCandidatePhoto[]) {
		layout = addPhotos(layout, photos);
	}

	function newHeading() {
		const result = addSection(layout);
		layout = result.layout;
		// The new heading's name field, so the contractor can type straight away.
		queueMicrotask(() => document.getElementById(`report-heading-${result.sectionId}`)?.focus());
	}

	function pickPartner(itemId: string) {
		if (!pairingFrom) return;
		layout = makePair(layout, pairingFrom, itemId);
		pairingFrom = null;
	}

	function remove(itemId: string) {
		if (pairingFrom === itemId) pairingFrom = null;
		layout = removeItem(layout, itemId);
	}

	const pairingPhoto = $derived.by(() => {
		if (!pairingFrom) return null;
		const item = [layout.top, ...layout.sections.map((section) => section.items)]
			.flat()
			.find((entry) => entry.id === pairingFrom);
		return item?.kind === 'photo' ? byId.get(item.fileId) : null;
	});
</script>

{#snippet thumb(fileId: string)}
	{@const photo = byId.get(fileId)}
	<span class="report-photo-layout__thumb">
		{#if photo}
			<FileThumb
				fileId={photo.file_id}
				displayName={photo.file_name}
				mimeType={photo.mime_type}
				kind="image"
				processingState="available"
				hasThumbnail={photo.has_thumbnail}
			/>
		{/if}
	</span>
{/snippet}

{#snippet words(fileId: string)}
	{@const photo = byId.get(fileId)}
	{#if photo}
		<span class="report-photo-layout__words">
			{#if photo.labels.length > 0}
				<span class="report-photo-layout__labels">{photo.labels.join(' · ')}</span>
			{/if}
			<span class="report-photo-layout__caption">{photo.caption || photo.file_name}</span>
		</span>
	{/if}
{/snippet}

{#snippet iconButton(label: string, icon: string, onclick: () => void, off = false)}
	<button
		type="button"
		class="report-photo-layout__icon-button"
		aria-label={label}
		title={label}
		disabled={disabled || off}
		{onclick}
	>
		<!-- eslint-disable-next-line svelte/no-at-html-tags -->
		{@html icon}
	</button>
{/snippet}

{#snippet itemRow(item: ArrangedItem)}
	<div
		class="report-photo-layout__item"
		class:report-photo-layout__item--pair={item.kind === 'pair'}
		class:report-photo-layout__item--pairing={pairingFrom === item.id}
	>
		<span
			class="report-photo-layout__handle"
			use:dragHandle
			aria-label={item.kind === 'pair' ? 'Drag this pair' : 'Drag this photo'}
		>
			<!-- eslint-disable-next-line svelte/no-at-html-tags -->
			{@html gripIcon}
		</span>

		{#if item.kind === 'photo'}
			{@render thumb(item.fileId)}
			{@render words(item.fileId)}
		{:else}
			<span class="report-photo-layout__pair">
				<span class="report-photo-layout__pair-side">
					<span class="report-photo-layout__pair-tag">Before</span>
					{@render thumb(item.beforeId)}
				</span>
				<span class="report-photo-layout__pair-side">
					<span class="report-photo-layout__pair-tag report-photo-layout__pair-tag--after"
						>After</span
					>
					{@render thumb(item.afterId)}
				</span>
			</span>
		{/if}

		<span class="report-photo-layout__controls">
			{#if pairingFrom && pairingFrom !== item.id}
				{#if item.kind === 'photo'}
					<Button size="small" variant="primary" {disabled} onclick={() => pickPartner(item.id)}>
						Use as After
					</Button>
				{/if}
			{:else if pairingFrom === item.id}
				<Button
					size="small"
					variant="secondary"
					variation="subtle"
					onclick={() => (pairingFrom = null)}
				>
					Cancel pair
				</Button>
			{:else}
				{@render iconButton(
					'Move up',
					arrowUpIcon,
					() => (layout = moveItem(layout, item.id, -1)),
					!canMoveItem(layout, item.id, -1)
				)}
				{@render iconButton(
					'Move down',
					arrowDownIcon,
					() => (layout = moveItem(layout, item.id, 1)),
					!canMoveItem(layout, item.id, 1)
				)}
				{#if item.kind === 'photo'}
					{@render iconButton(
						'Make a before/after pair with another photo',
						pairIcon,
						() => (pairingFrom = item.id),
						onReport.size < 2
					)}
				{:else}
					{@render iconButton(
						'Swap before and after',
						swapIcon,
						() => (layout = swapPair(layout, item.id))
					)}
					{@render iconButton(
						'Split the pair',
						unpairIcon,
						() => (layout = splitPair(layout, item.id))
					)}
				{/if}
				{@render iconButton(
					item.kind === 'pair' ? 'Take this pair off the report' : 'Take this photo off the report',
					closeIcon,
					() => remove(item.id)
				)}
			{/if}
		</span>
	</div>
{/snippet}

{#snippet itemZone(
	items: ArrangedItem[],
	onchange: (event: CustomEvent<DndEvent<ArrangedItem>>) => void,
	emptyHint: string
)}
	<div
		class="report-photo-layout__zone"
		use:dragHandleZone={{
			items,
			type: 'report-photo',
			flipDurationMs: FLIP_MS,
			dragDisabled: disabled || pairingFrom !== null,
			dropTargetStyle: {}
		}}
		onconsider={onchange}
		onfinalize={onchange}
	>
		{#each items as item (item.id)}
			<div class="report-photo-layout__cell" animate:flip={{ duration: FLIP_MS }}>
				{@render itemRow(item)}
			</div>
		{/each}
	</div>
	{#if items.length === 0}
		<p class="report-photo-layout__zone-hint">{emptyHint}</p>
	{/if}
{/snippet}

<div class="report-photo-layout">
	{#if candidates.length === 0}
		<p class="report-photo-layout__empty">This job has no photos yet.</p>
	{:else}
		{#if pairingPhoto}
			<p class="report-photo-layout__pairing" role="status">
				Pick the <strong>After</strong> photo to pair with
				<strong>{pairingPhoto.caption || pairingPhoto.file_name}</strong>.
			</p>
		{/if}

		{#if isEmpty(layout)}
			<p class="report-photo-layout__empty">
				No photos on the report yet. Add them below — photos labelled Before, During, After or
				Damage are sorted under those headings for you.
			</p>
		{:else}
			<!-- Photos above the first heading. Always a drop target, so a photo can be dragged back up here. -->
			{@render itemZone(layout.top, setTopItems, '')}

			<div
				class="report-photo-layout__sections"
				use:dragHandleZone={{
					items: layout.sections,
					type: 'report-section',
					flipDurationMs: FLIP_MS,
					dragDisabled: disabled || pairingFrom !== null,
					dropTargetStyle: {}
				}}
				onconsider={setSections}
				onfinalize={setSections}
			>
				{#each layout.sections as section, index (section.id)}
					{@const invalid = invalidSectionIds.includes(section.id) && !section.heading.trim()}
					<section
						class="report-photo-layout__section"
						aria-label={section.heading || 'New heading'}
						animate:flip={{ duration: FLIP_MS }}
					>
						<div class="report-photo-layout__section-head">
							<span
								class="report-photo-layout__handle"
								use:dragHandle
								aria-label="Drag this heading"
							>
								<!-- eslint-disable-next-line svelte/no-at-html-tags -->
								{@html gripIcon}
							</span>
							<div class="report-photo-layout__section-fields">
								<Input
									id={`report-heading-${section.id}`}
									label="Heading"
									value={section.heading}
									maxlength={80}
									required
									{invalid}
									errorMessage={invalid ? 'Give this heading a name.' : ''}
									{disabled}
									oninput={(event: Event) =>
										(layout = updateSection(layout, section.id, {
											heading: (event.currentTarget as HTMLInputElement).value
										}))}
								/>
								<Textarea
									id={`report-note-${section.id}`}
									label="Note for the customer (optional)"
									value={section.note}
									rows={2}
									maxlength={1000}
									showCount={false}
									{disabled}
									oninput={(event: Event) =>
										(layout = updateSection(layout, section.id, {
											note: (event.currentTarget as HTMLTextAreaElement).value
										}))}
								/>
							</div>
							<span class="report-photo-layout__controls">
								{@render iconButton(
									'Move heading up',
									arrowUpIcon,
									() => (layout = moveSection(layout, section.id, -1)),
									index === 0
								)}
								{@render iconButton(
									'Move heading down',
									arrowDownIcon,
									() => (layout = moveSection(layout, section.id, 1)),
									index === layout.sections.length - 1
								)}
								{@render iconButton(
									'Remove heading (its photos stay on the report)',
									closeIcon,
									() => (layout = removeSection(layout, section.id))
								)}
							</span>
						</div>
						{@render itemZone(
							section.items,
							(event) => setSectionItems(section.id, event),
							'No photos under this heading yet. Drag some here.'
						)}
					</section>
				{/each}
			</div>
		{/if}

		<div class="report-photo-layout__add-heading">
			<Button size="small" variant="secondary" {disabled} onclick={newHeading}>
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				<span class="report-photo-layout__button-icon" aria-hidden="true">{@html plusIcon}</span>
				Add heading
			</Button>
		</div>

		{#if notOnReport.length > 0}
			<div class="report-photo-layout__library">
				<div class="report-photo-layout__library-head">
					<h4 class="report-photo-layout__library-title">
						Job photos not on the report ({notOnReport.length})
					</h4>
					{#if notOnReport.length > 1}
						<Button
							size="small"
							variant="tertiary"
							disabled={disabled || pairingFrom !== null}
							onclick={() => add(notOnReport)}
						>
							Add all
						</Button>
					{/if}
				</div>
				<div class="report-photo-layout__library-grid">
					{#each notOnReport as photo (photo.file_id)}
						<button
							type="button"
							class="report-photo-layout__library-photo"
							aria-label={`Add ${photo.caption || photo.file_name} to the report`}
							disabled={disabled || pairingFrom !== null}
							onclick={() => add([photo])}
						>
							{@render thumb(photo.file_id)}
							<span class="report-photo-layout__library-add" aria-hidden="true">
								<!-- eslint-disable-next-line svelte/no-at-html-tags -->
								{@html plusIcon}
							</span>
							{#if photo.labels.length > 0 || photo.caption}
								<span class="report-photo-layout__library-words">
									{photo.labels.length > 0 ? photo.labels.join(' · ') : photo.caption}
								</span>
							{/if}
						</button>
					{/each}
				</div>
			</div>
		{/if}
	{/if}
</div>

<style lang="scss">
	.report-photo-layout {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__empty,
		&__zone-hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__zone-hint:empty {
			display: none;
		}

		&__pairing {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			border: var(--border-base) solid var(--color-interactive);
			background: var(--color-surface--background--subtle);
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
		}

		// Always tall enough to drop into, even when empty.
		&__zone {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			min-height: var(--space-large);
		}

		&__cell {
			outline: none;
		}

		&__item {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-small);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);

			&--pairing {
				border-color: var(--color-interactive);
				box-shadow: 0 0 0 1px var(--color-interactive);
			}
		}

		&__handle {
			display: inline-flex;
			flex-shrink: 0;
			align-items: center;
			justify-content: center;
			width: 24px;
			height: 32px;
			color: var(--color-text--secondary);
			cursor: grab;
			border-radius: var(--radius-small);

			&:focus-visible {
				outline: var(--border-thick) solid var(--color-interactive);
				outline-offset: 1px;
			}

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__thumb {
			display: block;
			flex-shrink: 0;
			width: 72px;
			overflow: hidden;
			border-radius: var(--radius-base);
		}

		&__words {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-smallest);
			min-width: 0;
			font-size: var(--typography--fontSize-small);
		}

		&__labels {
			overflow: hidden;
			color: var(--color-interactive);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__caption {
			display: -webkit-box;
			overflow: hidden;
			color: var(--color-text);
			overflow-wrap: anywhere;
			-webkit-box-orient: vertical;
			-webkit-line-clamp: 2;
			line-clamp: 2;
		}

		&__pair {
			display: flex;
			flex: 1;
			gap: var(--space-small);
			min-width: 0;
		}

		&__pair-side {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
		}

		&__pair-tag {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 700;
			letter-spacing: 0.04em;
			text-transform: uppercase;

			&--after {
				color: var(--color-success);
			}
		}

		&__controls {
			display: flex;
			flex-shrink: 0;
			flex-wrap: wrap;
			align-items: center;
			justify-content: flex-end;
			gap: var(--space-smallest);
			margin-left: auto;
		}

		&__icon-button {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			width: 32px;
			height: 32px;
			padding: 0;
			border: var(--border-base) solid transparent;
			border-radius: var(--radius-base);
			background: transparent;
			color: var(--color-text--secondary);
			cursor: pointer;

			&:hover:not(:disabled) {
				background: var(--color-surface--background--subtle);
				color: var(--color-heading);
			}

			&:focus-visible {
				outline: var(--border-thick) solid var(--color-interactive);
				outline-offset: 1px;
			}

			&:disabled {
				opacity: 0.35;
				cursor: not-allowed;
			}

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__sections {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}

		&__section {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
		}

		&__section-head {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
		}

		&__section-fields {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-small);
			min-width: 0;
		}

		&__add-heading {
			display: flex;
		}

		&__button-icon {
			display: inline-flex;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__library {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__library-head {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__library-title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__library-grid {
			display: grid;
			grid-template-columns: repeat(auto-fill, minmax(96px, 1fr));
			gap: var(--space-small);
		}

		&__library-photo {
			position: relative;
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			padding: 0;
			overflow: hidden;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			color: inherit;
			text-align: left;
			cursor: pointer;

			.report-photo-layout__thumb {
				width: 100%;
				border-radius: 0;
			}

			&:hover:not(:disabled) {
				border-color: var(--color-interactive);
			}

			&:focus-visible {
				outline: var(--border-thick) solid var(--color-interactive);
				outline-offset: 2px;
			}

			&:disabled {
				opacity: 0.5;
				cursor: not-allowed;
			}
		}

		&__library-add {
			position: absolute;
			top: var(--space-smaller);
			right: var(--space-smaller);
			display: inline-flex;
			align-items: center;
			justify-content: center;
			width: 24px;
			height: 24px;
			border-radius: 50%;
			background: var(--color-interactive);
			color: var(--color-surface);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__library-words {
			overflow: hidden;
			padding: 0 var(--space-small) var(--space-smaller);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			text-overflow: ellipsis;
			white-space: nowrap;
		}
	}

	// On a phone the controls drop under the photo so the row never overflows.
	@media (max-width: 560px) {
		.report-photo-layout__item {
			flex-wrap: wrap;
		}

		.report-photo-layout__controls {
			width: 100%;
		}
	}
</style>
