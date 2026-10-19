<script lang="ts">
	import type { Snippet } from 'svelte';

	let {
		variant = 'fill',
		children,
		class: className = ''
	}: {
		variant?: 'fill' | 'standard' | 'narrow' | 'two-panel' | 'open';
		children: Snippet;
		class?: string;
	} = $props();
</script>

<div class={`page-container page-container--${variant} ${className} scroll-y-auto`}>
	{@render children()}
</div>

<style lang="scss">
	.page-container {
		width: 100%;
		max-width: none;
		margin-inline: auto;
		background-color: var(--color-surface);
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);

		/* `open` lets the page sit straight on the app background — no white sheet, no padding — for screens
		   built from their own cards, like Jobs. */
		&--open {
			max-width: none;
			margin-inline: auto;
			border: 0;
			padding: 0;
			border-radius: 0;
			background-color: transparent;
		}
		&--standard {
			max-width: none;
			margin-inline: auto;
		}
		&--narrow {
			max-width: 640px;
			margin-inline: auto;
		}
		&--two-panel {
			display: grid;
			grid-template-columns: minmax(0, 1fr) 360px;
			align-items: start;
			gap: var(--space-large);
		}
	}
	@media (max-width: 1079px) {
		.page-container--two-panel {
			grid-template-columns: 1fr;
		}
	}
</style>
