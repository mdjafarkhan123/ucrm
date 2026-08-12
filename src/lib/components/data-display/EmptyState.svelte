<script lang="ts">
	import type { Snippet } from 'svelte';
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';
	let {
		title,
		description,
		icon = inboxIcon,
		action
	}: { title: string; description?: string; icon?: string; action?: Snippet } = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="empty-state" aria-labelledby="empty-state-title">
	<div class="empty-state__icon" aria-hidden="true">{@html icon}</div>
	<h2 id="empty-state-title">{title}</h2>
	{#if description}<p>{description}</p>{/if}
	{#if action}<div class="empty-state__action">{@render action()}</div>{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.empty-state {
		display: grid;
		justify-items: center;
		gap: var(--space-base);
		padding: var(--space-extravagant) var(--space-large);
		border: var(--border-base) dashed var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-text--secondary);
		text-align: center;
	}
	.empty-state__icon {
		display: grid;
		place-items: center;
		width: var(--space-largest);
		height: var(--space-largest);
		border-radius: var(--radius-circle);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.empty-state__icon :global(svg) {
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
</style>
