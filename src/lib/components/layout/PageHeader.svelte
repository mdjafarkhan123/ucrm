<script lang="ts">
	import type { Snippet } from 'svelte';
	let {
		title,
		description,
		eyebrow,
		actions,
		class: className = ''
	}: {
		title: string;
		description?: string;
		eyebrow?: string;
		actions?: Snippet;
		class?: string;
	} = $props();
</script>

<header class={`page-header ${className}`}>
	<div class="page-header__copy">
		{#if eyebrow}<p class="page-header__eyebrow">{eyebrow}</p>{/if}
		<h1>{title}</h1>
		{#if description}<p class="page-header__description">{description}</p>{/if}
	</div>
	{#if actions}<div class="page-header__actions">{@render actions()}</div>{/if}
</header>

<style lang="scss">
	.page-header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-large);
		padding-bottom: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.page-header__eyebrow {
		margin-bottom: var(--space-small);
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}
	h1 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 900;
		line-height: var(--typography--lineHeight-minuscule);
	}
	.page-header__description {
		max-width: 65ch;
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
	}
	.page-header__actions {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
	}
	@media (max-width: 639px) {
		.page-header {
			flex-direction: column;
		}
		h1 {
			font-size: 28px;
		}
		.page-header__actions {
			width: 100%;
		}
	}
</style>
