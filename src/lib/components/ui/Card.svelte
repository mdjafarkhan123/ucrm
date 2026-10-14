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

	:global(:root:has(.app-shell[data-presentation='classic'])) .card {
		border: 0;
		border-radius: 20px;
		background: var(--classic2-surface);
		box-shadow:
			inset 0 0 0 1px var(--classic2-border),
			0 1px 2px var(--classic2-shadow-near),
			0 10px 28px var(--classic2-shadow-far);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .card__heading {
		color: var(--classic2-ink);
		font-size: var(--classic2-font-card);
	}
</style>
