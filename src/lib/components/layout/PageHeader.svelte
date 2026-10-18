<script lang="ts">
	import type { Snippet } from 'svelte';
	let {
		title,
		description,
		icon,
		tone = 'inactive',
		actions,
		titleId,
		class: className = ''
	}: {
		title: string;
		description?: string;
		/** A Tabler icon (raw SVG) on a 40 tile in the page's record or section colour, before the title. */
		icon?: string;
		/** The colour family of the icon tile, the same as the page's sidebar item: `job`, `quote`, `time`… */
		tone?: string;
		actions?: Snippet;
		/** The title's id, for a page section labelled by it. */
		titleId?: string;
		class?: string;
	} = $props();
</script>

<!-- The page's title row: the icon tile, a 24 title with the description under it, and the page's actions
     centred at the right. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<header class={['page-header', className]}>
	{#if icon}
		<span
			class="page-header__tile"
			style:--page-header-tone={`var(--color-${tone})`}
			style:--page-header-tone-surface={`var(--color-${tone}--surface)`}
			aria-hidden="true">{@html icon}</span
		>
	{/if}
	<div class="page-header__copy">
		<h1 id={titleId}>{title}</h1>
		{#if description}<p class="page-header__description">{description}</p>{/if}
	</div>
	{#if actions}<div class="page-header__actions">{@render actions()}</div>{/if}
</header>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.page-header {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		padding-top: var(--space-small);
		margin-bottom: var(--space-large);
	}
	.page-header__tile {
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		width: 40px;
		height: 40px;
		border-radius: var(--radius-tile-large);
		color: var(--page-header-tone);
		background: var(--page-header-tone-surface);

		:global(svg) {
			display: block;
			width: 20px;
			height: 20px;
		}
	}
	.page-header__copy {
		display: grid;
		flex: 1;
		min-width: 0;
		gap: 2px;
	}
	h1 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		font-weight: 700;
		letter-spacing: -0.5px;
		line-height: 1.2;
	}
	.page-header__description {
		max-width: 65ch;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-large);
	}
	.page-header__actions {
		display: flex;
		flex: 0 0 auto;
		flex-wrap: wrap;
		align-items: center;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	@media (max-width: 639px) {
		.page-header {
			flex-wrap: wrap;
		}
		.page-header__actions {
			width: 100%;
			justify-content: flex-start;
		}
	}
</style>
