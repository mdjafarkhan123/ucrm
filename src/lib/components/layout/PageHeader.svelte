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
		/** A small label above the title that names the area the page belongs to, e.g. "Work & money". */
		eyebrow?: string;
		actions?: Snippet;
		class?: string;
	} = $props();
</script>

<header class={`page-header ${className}`}>
	<div class="page-header__copy">
		{#if eyebrow}
			<p class="page-header__eyebrow">
				<span class="page-header__eyebrow-dot" aria-hidden="true"></span>{eyebrow}
			</p>
		{/if}
		<h1>{title}</h1>
		{#if description}<p class="page-header__description">{description}</p>{/if}
	</div>
	{#if actions}<div class="page-header__actions">{@render actions()}</div>{/if}
</header>

<style lang="scss">
	.page-header {
		display: flex;
		align-items: flex-end;
		justify-content: space-between;
		gap: var(--space-large);
		padding-top: var(--space-small);
		margin-bottom: var(--space-large);
	}
	.page-header__copy {
		display: grid;
		flex: 1;
		min-width: 0;
		gap: 6px;
	}
	.page-header__eyebrow {
		display: flex;
		align-items: center;
		gap: 6px;
		color: var(--color-text--secondary);
		font-size: 11px;
		font-weight: 700;
		letter-spacing: 1px;
		text-transform: uppercase;
	}
	.page-header__eyebrow-dot {
		width: 6px;
		height: 6px;
		border-radius: var(--radius-circle);
		background: var(--color-interactive);
	}
	h1 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 900;
		letter-spacing: -1.2px;
		line-height: 1.1;
	}
	.page-header__description {
		max-width: 65ch;
		color: var(--color-text--secondary);
		font-size: 15px;
		font-weight: 500;
		line-height: var(--typography--lineHeight-large);
	}
	.page-header__actions {
		display: flex;
		flex: 0 0 auto;
		flex-wrap: wrap;
		align-items: center;
		justify-content: flex-end;
		gap: 10px;
		padding-bottom: var(--space-smaller);
	}
	@media (max-width: 639px) {
		.page-header {
			flex-direction: column;
			align-items: stretch;
		}
		h1 {
			font-size: 28px;
			letter-spacing: -0.8px;
		}
		.page-header__actions {
			width: 100%;
			justify-content: flex-start;
		}
	}
</style>
