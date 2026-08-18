<script lang="ts">
	import type { Snippet } from 'svelte';

	// The bar of actions that stays in reach at the bottom of a long page. Create and edit forms show it
	// always; a detail page shows it only once something is waiting to be saved.
	//
	// It is pinned to the bottom of the content area rather than sticky. Sticky only lets an element float
	// inside its own container, and this bar is always the last thing in that container, so there was no
	// room below it to float through — it just sat at the very bottom of the page where nobody scrolled to.
	// `AppShell` publishes where the content column starts and ends, so the pinned bar lines up with the
	// page underneath it and follows the sidebar when it collapses.
	let { children, class: className = '' }: { children: Snippet; class?: string } = $props();

	// The bar floats over the page, so the page has to end this much earlier or the bar covers its last
	// block. Measured rather than guessed, because the buttons stack on a narrow screen.
	let barHeight = $state(0);
</script>

<div
	class="sticky-action-bar__spacer"
	style={`height: calc(${barHeight}px + var(--space-large))`}
	aria-hidden="true"
></div>

<footer class={`sticky-action-bar ${className}`} bind:clientHeight={barHeight}>
	{@render children()}
</footer>

<style lang="scss">
	.sticky-action-bar {
		position: fixed;
		right: var(--shell-content-right, var(--space-large));
		bottom: var(--shell-edge, var(--space-large));
		left: var(--shell-content-left, var(--space-large));
		z-index: var(--elevation-menu);
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-base) var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
		transition:
			left var(--timing-base) ease-out,
			right var(--timing-base) ease-out;
	}

	// Holds the bar's place in the flow so the last block on the page is never hidden behind it.
	.sticky-action-bar__spacer {
		flex: 0 0 auto;
	}

	@media (max-width: 767px) {
		.sticky-action-bar {
			flex-direction: column-reverse;
			align-items: stretch;
		}
	}
</style>
