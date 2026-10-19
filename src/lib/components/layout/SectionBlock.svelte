<script lang="ts">
	import type { Snippet } from 'svelte';
	import CardHeader from '$lib/components/ui/CardHeader.svelte';
	import sectionIcon from '@tabler/icons/outline/layout-list.svg?raw';

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
		tone = 'inactive',
		class: className = ''
	}: {
		title: string;
		icon?: string;
		hint?: string;
		subtitle?: string;
		variant?: 'plain' | 'filled';
		level?: 2 | 3 | 4;
		/** A semantic group within a form, rather than a separate section card. */
		form?: boolean;
		id?: string;
		actions?: Snippet;
		children: Snippet;
		/** The record or app area this section describes. */
		tone?: string;
		class?: string;
	} = $props();

	const uid = $props.id();
	const titleId = $derived(`${id ?? uid}-title`);
</script>

{#if form}
	<fieldset
		class={['section-block', 'section-block--group', `section-block--${variant}`, className]}
		{id}
	>
		<legend class="section-block__title">{title}</legend>
		{#if actions}<div class="section-block__actions">{@render actions()}</div>{/if}
		{#if subtitle ?? hint}<p class="section-block__hint">{subtitle ?? hint}</p>{/if}
		{@render children()}
	</fieldset>
{:else}
	<section
		class={['section-block', 'section-block--concept', className]}
		{id}
		aria-labelledby={titleId}
	>
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
	</section>
{/if}

<style lang="scss">
	.section-block {
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
		min-width: 0;
		margin: 0;
		padding: 0;
	}
	.section-block--concept {
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
	}
	.section-block__concept-body {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		padding: var(--space-medium);
	}
	.section-block--flush > .section-block__concept-body {
		gap: 0;
		padding: 0;
	}
	.section-block--group {
		position: relative;
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);
		padding-top: var(--space-base);
		border: 0;
		border-top: var(--border-base) solid var(--color-border);
	}
	.section-block__title {
		float: left;
		width: 100%;
		padding: 0;
		color: var(--color-heading);
		font-size: var(--space-base);
		font-weight: 600;
		line-height: var(--typography--lineHeight-tight);
	}
	.section-block__hint {
		margin: calc(-1 * var(--space-small)) 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
	}
	.section-block__actions {
		align-self: flex-end;
	}
</style>
