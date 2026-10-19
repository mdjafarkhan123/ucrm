<script lang="ts">
	import type { Snippet } from 'svelte';
	import CardHeader from '$lib/components/ui/CardHeader.svelte';
	import sectionIcon from '@tabler/icons/outline/layout-list.svg?raw';

	let {
		title,
		icon,
		count,
		description,
		flush = false,
		compact = true,
		actions,
		children,
		tone = 'inactive',
		class: className = ''
	}: {
		title: string;
		icon?: string;
		count?: number;
		description?: string;
		/** Rows provide their own padding when the body runs edge to edge. */
		flush?: boolean;
		compact?: boolean;
		tone?: string;
		actions?: Snippet;
		children: Snippet;
		class?: string;
	} = $props();
	const uid = $props.id();
	const hint = $derived(
		[count !== undefined ? String(count) : '', description].filter(Boolean).join(' · ')
	);
</script>

<section
	class={['rail-card', 'rail-card--concept', flush && 'rail-card--flush', className]}
	aria-labelledby={uid}
>
	<CardHeader
		{title}
		hint={hint || undefined}
		icon={icon ?? sectionIcon}
		{tone}
		{compact}
		{actions}
		id={uid}
	/>
	{@render children()}
</section>

<style lang="scss">
	.rail-card {
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		min-width: 0;
		padding: 0 0 var(--space-base);
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: none;
	}
	.rail-card > :global(:where(:not(.card-header))) {
		min-width: 0;
		max-width: calc(100% - 2 * var(--space-base));
		margin-inline: var(--space-base);
	}
	.rail-card--flush {
		gap: 0;
		padding: 0;
	}
	.rail-card--flush > :global(:where(:not(.card-header))) {
		max-width: 100%;
		margin: 0;
	}
</style>
