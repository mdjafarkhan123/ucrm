<script lang="ts">
	import type { Snippet } from 'svelte';

	let {
		children,
		heading,
		class: className = ''
	}: {
		children?: Snippet;
		heading?: string;
		class?: string;
	} = $props();
</script>

<article class={`card ${className}`}>
	{#if heading}<h2 class="card__heading">{heading}</h2>{/if}
	{#if children}{@render children()}{/if}
</article>

<style lang="scss">
	.card {
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);

		&__heading {
			margin-bottom: var(--space-base);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
			font-weight: 700;
			line-height: var(--typography--lineHeight-tight);
		}
	}
</style>
