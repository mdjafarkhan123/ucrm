<script lang="ts">
	import type { Snippet } from 'svelte';
	import CardHeader from './CardHeader.svelte';
	import layoutIcon from '@tabler/icons/outline/layout.svg?raw';

	let {
		children,
		heading,
		icon = layoutIcon,
		tone = 'inactive',
		hint,
		actions,
		class: className = ''
	}: {
		children?: Snippet;
		heading?: string;
		icon?: string;
		tone?: string;
		hint?: string;
		actions?: Snippet;
		class?: string;
	} = $props();
</script>

<article class={['card', heading && 'card--headed', className]}>
	{#if heading}
		<div class="card__header"><CardHeader title={heading} {icon} {tone} {hint} {actions} /></div>
	{/if}
	{#if children}{@render children()}{/if}
</article>

<style lang="scss">
	.card {
		min-width: 0;
		padding: var(--space-medium);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: none;

		&--headed {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}

		&__header {
			margin: calc(-1 * var(--space-medium)) calc(-1 * var(--space-medium)) var(--space-smaller);
		}
	}
</style>
