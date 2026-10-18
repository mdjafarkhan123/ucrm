<script lang="ts">
	import type { Snippet } from 'svelte';

	// The one title area every white card with a title starts with (Pencil: "Card header" on the Parts board):
	// a 40 icon tile in the card's meaning colour, the title with an optional quiet hint under it, the card's
	// actions at the right, and a hairline underneath.
	let {
		title,
		hint,
		icon,
		tone = 'inactive',
		level = 2,
		id,
		compact = false,
		actions,
		class: className = ''
	}: {
		title: string;
		hint?: string | null;
		/** A Tabler icon (raw SVG) on the tile. */
		icon: string;
		/** The tile's colour family: a record (`job`, `invoice`…), a section (`time`, `growth`…) or a status. */
		tone?: string;
		/** The heading level, so headings stay in order on the page. */
		level?: 2 | 3 | 4;
		/** The heading's id, for a card that is labelled by its title. */
		id?: string;
		/** The tighter padding of a card in a narrow right column. */
		compact?: boolean;
		actions?: Snippet;
		class?: string;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<header class={['card-header', compact && 'card-header--compact', className]}>
	<span
		class="card-header__tile"
		style:--card-header-tone={`var(--color-${tone})`}
		style:--card-header-tone-surface={`var(--color-${tone}--surface)`}
		aria-hidden="true">{@html icon}</span
	>
	<div class="card-header__copy">
		<svelte:element this={`h${level}`} {id} class="card-header__title">{title}</svelte:element>
		{#if hint}<p class="card-header__hint">{hint}</p>{/if}
	</div>
	{#if actions}<div class="card-header__actions">{@render actions()}</div>{/if}
</header>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.card-header {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		padding: var(--space-base) var(--space-medium);
		border-bottom: var(--border-base) solid var(--color-border);

		&--compact {
			padding: 14px var(--space-base);
		}
	}
	.card-header__tile {
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		width: 40px;
		height: 40px;
		border-radius: var(--radius-tile-large);
		color: var(--card-header-tone);
		background: var(--card-header-tone-surface);

		:global(svg) {
			display: block;
			width: 20px;
			height: 20px;
		}
	}
	.card-header__copy {
		display: grid;
		flex: 1;
		min-width: 0;
		gap: 2px;
	}
	.card-header__title {
		overflow: hidden;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-larger);
		font-weight: 600;
		letter-spacing: -0.2px;
		line-height: 1.25;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.card-header__hint {
		overflow: hidden;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.card-header__actions {
		display: flex;
		flex: 0 0 auto;
		align-items: center;
		gap: var(--space-small);
	}
</style>
