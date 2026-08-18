<script lang="ts">
	import type { Snippet } from 'svelte';

	let {
		variant = 'fill',
		children,
		class: className = ''
	}: {
		variant?: 'fill' | 'standard' | 'narrow' | 'two-panel';
		children: Snippet;
		class?: string;
	} = $props();
</script>

<div class={`page-container page-container--${variant} ${className}`}>
	{@render children()}
</div>

<style lang="scss">
	.page-container {
		width: 100%;

		&--standard {
			max-width: 1280px;
			margin-inline: auto;
		}
		&--narrow {
			max-width: 640px;
			margin-inline: auto;
		}
		&--two-panel {
			display: grid;
			grid-template-columns: minmax(0, 1.35fr) minmax(320px, 1fr);
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
