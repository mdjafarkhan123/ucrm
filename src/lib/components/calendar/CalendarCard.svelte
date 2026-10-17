<script lang="ts">
	import type { Snippet } from 'svelte';

	// The one card a calendar lives in: the toolbar on top, a divider, the grid, and a footer that explains the
	// colours. The grid scrolls inside the card, so the toolbar and the footer stay in view however long the
	// day is. The caller gives the card its height (a flex child that fills the page, or a fixed height).

	let {
		bar,
		legend,
		children,
		class: className = ''
	}: {
		bar: Snippet;
		legend?: Snippet;
		children: Snippet;
		class?: string;
	} = $props();
</script>

<section class="calendar-card {className}">
	<div class="calendar-card__bar">{@render bar()}</div>
	<div class="calendar-card__body">{@render children()}</div>
	{#if legend}
		<footer class="calendar-card__legend">{@render legend()}</footer>
	{/if}
</section>

<style lang="scss">
	.calendar-card {
		display: flex;
		flex-direction: column;
		min-width: 0;
		min-height: 0;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background-color: var(--color-surface);
		overflow: hidden;
	}

	.calendar-card__bar {
		flex: 0 0 auto;
		padding: var(--space-base) 20px;
		border-bottom: var(--border-base) solid var(--color-border);
	}

	// The grid takes whatever height is left and scrolls inside it.
	.calendar-card__body {
		display: flex;
		flex: 1 1 auto;
		flex-direction: column;
		min-height: 0;
	}

	.calendar-card__legend {
		flex: 0 0 auto;
		border-top: var(--border-base) solid var(--color-border);
	}
</style>
