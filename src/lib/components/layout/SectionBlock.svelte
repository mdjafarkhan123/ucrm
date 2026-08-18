<script lang="ts">
	import type { Snippet } from 'svelte';

	// One bordered block with its title sitting on the border line. Form blocks render as a real
	// fieldset/legend so grouped inputs are announced as a group; everything else renders as a section
	// with a heading, because fieldset is only correct around form controls.
	let {
		title,
		icon,
		hint,
		variant = 'plain',
		level = 2,
		form = false,
		id,
		actions,
		children,
		class: className = ''
	}: {
		title: string;
		icon?: string;
		hint?: string;
		variant?: 'plain' | 'filled';
		level?: 2 | 3 | 4;
		form?: boolean;
		id?: string;
		actions?: Snippet;
		children: Snippet;
		class?: string;
	} = $props();

	const blockClass = $derived(
		`section-block section-block--${variant} ${form ? '' : 'section-block--standalone'} ${className}`
	);
	const titleId = $derived(id ? `${id}-title` : undefined);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet titleContent()}
	{#if icon}<span class="section-block__icon" aria-hidden="true">{@html icon}</span>{/if}
	<span class="section-block__title-text">{title}</span>
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
	<section class={blockClass} {id} aria-labelledby={titleId}>
		{#if level === 2}
			<h2 class="section-block__title" id={titleId}>{@render titleContent()}</h2>
		{:else if level === 3}
			<h3 class="section-block__title" id={titleId}>{@render titleContent()}</h3>
		{:else}
			<h4 class="section-block__title" id={titleId}>{@render titleContent()}</h4>
		{/if}
		{#if actions}<div class="section-block__actions">{@render actions()}</div>{/if}
		{@render body()}
	</section>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.section-block {
		position: relative;
		display: flex;
		flex-direction: column;
		// Room for the title and any actions that sit on the top border line.
		margin-top: var(--space-slim);
		gap: var(--space-base);
		padding: var(--space-large);
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

		&__hint {
			margin-top: calc(var(--space-small) * -1);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	@media (max-width: 767px) {
		.section-block {
			padding: var(--space-base);
		}
	}
</style>
