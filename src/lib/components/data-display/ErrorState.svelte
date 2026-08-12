<script lang="ts">
	import type { Snippet } from 'svelte';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	let {
		title = 'Something went wrong',
		description = 'We could not load this information. Try again.',
		retry,
		action
	}: { title?: string; description?: string; retry?: () => void; action?: Snippet } = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="error-state" aria-labelledby="error-state-title" role="alert">
	<div class="error-state__icon" aria-hidden="true">{@html alertIcon}</div>
	<h2 id="error-state-title">{title}</h2>
	<p>{description}</p>
	{#if retry}<button type="button" onclick={retry}>Try Again</button>{/if}
	{#if action}<div>{@render action()}</div>{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.error-state {
		display: grid;
		justify-items: center;
		gap: var(--space-base);
		padding: var(--space-extravagant) var(--space-large);
		border: var(--border-base) solid var(--color-critical);
		border-radius: var(--radius-base);
		color: var(--color-text--secondary);
		text-align: center;
	}
	.error-state__icon {
		display: grid;
		place-items: center;
		width: var(--space-largest);
		height: var(--space-largest);
		border-radius: var(--radius-circle);
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
	.error-state__icon :global(svg) {
		width: 24px;
		height: 24px;
	}
	h2 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-larger);
		line-height: var(--typography--lineHeight-tight);
	}
	p {
		max-width: 48ch;
		line-height: var(--typography--lineHeight-large);
	}
	button {
		min-height: 40px;
		padding: 0 var(--space-base);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		color: var(--color-interactive--subtle);
		background: var(--color-surface);
		font-weight: 600;
	}
	button:hover,
	button:focus-visible {
		background: var(--color-surface--hover);
	}
	button:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
</style>
