<script lang="ts">
	import type { Snippet } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';

	// The panel a list page drops open under its search box. Every list filters differently, so this owns
	// only the shape: a bordered strip holding the fields, with Clear filters on the end once something is
	// actually set. The fields themselves go in as `FilterField`s.
	let {
		children,
		onClear,
		class: className = ''
	}: {
		children: Snippet;
		/** Omit while nothing is filtered and the Clear button is not drawn. */
		onClear?: () => void;
		class?: string;
	} = $props();
</script>

<div class={`filter-bar ${className}`}>
	{@render children()}
	{#if onClear}
		<Button variant="tertiary" size="small" onclick={onClear}>Clear filters</Button>
	{/if}
</div>

<style lang="scss">
	.filter-bar {
		display: flex;
		flex-wrap: wrap;
		align-items: end;
		gap: var(--space-base);
		margin-bottom: var(--space-large);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}
</style>
