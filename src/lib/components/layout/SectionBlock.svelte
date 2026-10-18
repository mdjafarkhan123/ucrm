<script lang="ts">
	import { getContext, type Snippet } from 'svelte';
	import CardHeader from '$lib/components/ui/CardHeader.svelte';
	import sectionIcon from '@tabler/icons/outline/layout-list.svg?raw';

	// One bordered block with its title sitting on the border line. Form blocks render as a real
	// fieldset/legend so grouped inputs are announced as a group; everything else renders as a section
	// with a heading, because fieldset is only correct around form controls.
	let {
		title,
		icon,
		hint,
		subtitle,
		variant = 'plain',
		level = 2,
		form = false,
		id,
		actions,
		children,
		tone = 'job',
		class: className = ''
	}: {
		title: string;
		icon?: string;
		hint?: string;
		/** App look only: a quiet line directly under the title, inside the card header. */
		subtitle?: string;
		variant?: 'plain' | 'filled';
		level?: 2 | 3 | 4;
		form?: boolean;
		id?: string;
		actions?: Snippet;
		children: Snippet;
		/** Colour of the title tile in the approved job concept. */
		tone?: string;
		class?: string;
	} = $props();

	const blockClass = $derived(
		`section-block section-block--${variant} ${form ? '' : 'section-block--standalone'} ${subtitle ? 'section-block--has-subtitle' : ''} ${className}`
	);
	const titleId = $derived(id ? `${id}-title` : undefined);
	const conceptJob = getContext<boolean>('concept-job-details') ?? false;
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet titleContent()}
	{#if icon}<span class="section-block__icon" aria-hidden="true">{@html icon}</span>{/if}
	<span class="section-block__title-text">{title}</span>
{/snippet}

{#snippet subtitleLine()}
	{#if subtitle}<p class="section-block__subtitle">{subtitle}</p>{/if}
{/snippet}

{#snippet body()}
	{#if hint}<p class="section-block__hint">{hint}</p>{/if}
	{@render children()}
{/snippet}

{#if form}
	<fieldset class={blockClass} {id}>
		<legend class="section-block__title">{@render titleContent()}</legend>
		{#if actions}<div class="section-block__actions">{@render actions()}</div>{/if}
		{@render body()}
	</fieldset>
{:else}
	<section
		class={[blockClass, conceptJob && 'section-block--concept']}
		{id}
		aria-labelledby={titleId}
	>
		{#if conceptJob}
			<CardHeader
				{title}
				hint={subtitle ?? hint}
				icon={icon ?? sectionIcon}
				{tone}
				{level}
				id={titleId}
				{actions}
			/>
			<div class="section-block__concept-body">{@render children()}</div>
		{:else}
			{#if level === 2}
				<h2 class="section-block__title" id={titleId}>{@render titleContent()}</h2>
				{@render subtitleLine()}
			{:else if level === 3}
				<h3 class="section-block__title" id={titleId}>{@render titleContent()}</h3>
				{@render subtitleLine()}
			{:else}
				<h4 class="section-block__title" id={titleId}>{@render titleContent()}</h4>
				{@render subtitleLine()}
			{/if}
			{#if actions}<div class="section-block__actions">{@render actions()}</div>{/if}
			{@render body()}
		{/if}
	</section>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.section-block--concept,
	:global(.record-detail--cards) .section-block--concept {
		display: block;
		overflow: hidden;
		margin: 0;
		padding: 0;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
	}
	.section-block__concept-body {
		padding: var(--space-medium);
	}
	.section-block {
		position: relative;
		display: flex;
		flex-direction: column;
		// Room for the title and any actions that sit on the top border line.
		margin-top: var(--space-slim);
		gap: var(--space-base);
		padding: var(--space-large) var(--space-slim);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);

		&--filled {
			background: var(--color-surface--background);
		}

		// The heading has to break the border the way a legend does. It paints over the line with the
		// colour of whatever the block is sitting on, which callers set when that is not the card surface.
		&--standalone {
			.section-block__title {
				position: absolute;
				top: 0;
				left: var(--space-base);
				max-width: calc(100% - var(--space-larger));
				padding-inline: var(--space-small);
				background: var(--section-block-notch, var(--color-surface));
				transform: translateY(-50%);
			}
		}

		&__title {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 700;
			line-height: var(--typography--lineHeight-tight);
		}

		&__title-text {
			overflow: hidden;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__icon :global(svg) {
			display: block;
			width: 18px;
			height: 18px;
			color: var(--color-icon--secondary);
		}

		&__actions {
			position: absolute;
			top: 0;
			right: var(--space-base);
			padding-inline: var(--space-small);
			background: var(--section-block-notch, var(--color-surface));
			transform: translateY(-50%);
		}

		// Only drawn in the App look; the older bordered block has no room for it.
		&__subtitle {
			display: none;
		}

		&__hint {
			margin-top: calc(var(--space-small) * -1);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	// App look (inside `RecordDetailLayout cards`): the block becomes a white card whose title sits in its own
	// header row, with the actions at the far end, instead of a bordered box with the title on its border.
	// Content below the header gets the card's 24px side padding; a block that draws edge-to-edge rows or
	// a table adds `section-block--flush` and pads what needs it itself.
	:global(.record-detail--cards) .section-block {
		display: grid;
		overflow: clip;
		margin-top: 0;
		gap: 0;
		padding: 0;
		border-color: var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		grid-template-columns: minmax(0, 1fr) auto;
		align-content: start;

		> :global(*) {
			grid-column: 1 / -1;
		}
		> :global(.section-block__title),
		> :global(.section-block__actions) {
			position: static;
			grid-column: auto;
			grid-row: 1;
			max-width: none;
			padding: 20px 24px 16px;
			background: transparent;
			transform: none;
			align-self: center;
		}
		> :global(.section-block__actions) {
			padding-left: 0;
		}
		> :global(.section-block__title) {
			font-size: var(--typography--fontSize-large);
			letter-spacing: -0.2px;
		}
		:global(.section-block__icon) {
			display: none;
		}
		// A lone pencil at the card's top corner keeps a border, so it reads as a button.
		> :global(.section-block__actions) :global(.pencil-button--tertiary) {
			border-color: var(--color-border--interactive);
			background: var(--color-surface);
		}
		// A subtitle sits in the header's second row, under the title, while the actions stay centred on both.
		&.section-block--has-subtitle {
			> :global(.section-block__title) {
				padding-bottom: 3px;
			}
			> :global(.section-block__actions) {
				grid-row: 1 / span 2;
			}
			> :global(.section-block__subtitle) {
				display: block;
				grid-column: 1;
				grid-row: 2;
				margin: 0;
				padding: 0 24px 16px;
				color: var(--color-text--secondary);
				font-size: 13px;
				font-weight: 500;
			}
		}
		> :global(.section-block__hint) {
			margin: -12px 24px 20px;
			font-size: 13px;
			font-weight: 500;
		}
		// With a quiet line under the title, the actions sit beside both lines and the two lines pack together.
		&:has(> :global(.section-block__hint)) {
			> :global(.section-block__title) {
				padding-bottom: 0;
			}
			> :global(.section-block__hint) {
				grid-column: 1;
				grid-row: 2;
				margin: 3px 24px 20px;
			}
			> :global(.section-block__actions) {
				grid-row: 1 / span 2;
			}
		}

		// The pencil on a card header is a small bordered button, as in the approved designs.
		:global(.section-block__actions .pencil-button) {
			width: 40px;
			height: 36px;
			color: var(--color-text--secondary);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
			&:hover:not(:disabled),
			&:focus-visible:not(:disabled) {
				border-color: var(--color-border--interactive);
				color: var(--color-heading);
				background: var(--color-surface--hover);
			}
		}
	}
	// Low specificity on purpose, so a block's own contents can set their own margin where they differ.
	:global(.record-detail--cards)
		.section-block
		> :global(:where(:not(.section-block__title, .section-block__actions, .section-block__hint))) {
		width: auto;
		margin: 0 24px 24px;
	}
	:global(.record-detail--cards)
		.section-block--flush
		> :global(:where(:not(.section-block__title, .section-block__actions, .section-block__hint))) {
		margin: 0;
	}

	@media (max-width: 767px) {
		.section-block {
			padding: var(--space-base);
		}
	}
	:global(.record-detail--cards) .section-block--concept {
		display: block;
		border-radius: var(--radius-large);
	}
	:global(.record-detail--cards) .section-block--concept > :global(.card-header),
	:global(.record-detail--cards) .section-block--concept > .section-block__concept-body {
		width: 100%;
		margin: 0;
	}
	:global(.record-detail--cards) .section-block--concept > .section-block__concept-body {
		padding: var(--space-medium);
	}
	// A flush card draws its own edge-to-edge rows or table, so its body adds no padding.
	:global(.record-detail--cards) .section-block--concept.section-block--flush > .section-block__concept-body {
		padding: 0;
	}
</style>
