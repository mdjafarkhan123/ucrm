<script lang="ts">
	import type { Snippet } from 'svelte';

	// A card in a page's right rail. The title sits inside the card, not on its border — that border-notch
	// treatment belongs to the main column. See `.claude/skills/design/section-block.md`.
	let {
		title,
		icon,
		count,
		actions,
		children,
		class: className = ''
	}: {
		title: string;
		icon?: string;
		count?: number;
		actions?: Snippet;
		children: Snippet;
		class?: string;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class={`rail-card ${className}`}>
	<header class="rail-card__header">
		<h2 class="rail-card__title">
			{#if icon}<span class="rail-card__icon" aria-hidden="true">{@html icon}</span>{/if}
			{title}{#if count !== undefined}&nbsp;({count}){/if}
		</h2>
		{#if actions}<div class="rail-card__actions">{@render actions()}</div>{/if}
	</header>
	{@render children()}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.rail-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);

		&__header {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__title {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
			font-weight: 700;
			line-height: var(--typography--lineHeight-tight);
		}

		&__icon :global(svg) {
			display: block;
			width: 20px;
			height: 20px;
			color: var(--color-icon--secondary);
		}
	}

	// App look (inside `RecordDetailLayout cards`): 8px card, no shadow, a 16px/700 title in a header row
	// with 20px side padding. Rows placed straight in the card may run edge to edge.
	:global(.record-detail--cards) .rail-card {
		gap: 12px;
		padding: 18px 20px 20px;
		box-shadow: none;

		.rail-card__title {
			font-size: var(--typography--fontSize-large);
			letter-spacing: -0.2px;
		}
		.rail-card__icon {
			display: none;
		}
	}
</style>
