<script lang="ts">
	import Sidebar, { type NavItem } from './Sidebar.svelte';

	let {
		open = $bindable(false),
		items,
		brand,
		eyebrow,
		onnavigate
	}: { open?: boolean; items: NavItem[]; brand?: string; eyebrow?: string; onnavigate?: () => void } = $props();
</script>

{#if open}
	<div class="mobile-nav">
		<button
			class="mobile-nav__backdrop"
			type="button"
			aria-label="Close navigation"
			onclick={() => (open = false)}
		></button>
		<div class="mobile-nav__panel"><Sidebar {items} {brand} {eyebrow} onnavigate={() => { open = false; onnavigate?.(); }} /></div>
	</div>
{/if}

<style lang="scss">
	.mobile-nav {
		position: fixed;
		z-index: var(--elevation-modal);
		inset: 0;
		display: flex;
	}
	.mobile-nav__backdrop {
		position: absolute;
		inset: 0;
		border: 0;
		background: var(--color-overlay);
	}
	.mobile-nav__panel {
		position: relative;
		z-index: var(--elevation-modal);
		width: min(86vw, 320px);
		background: var(--color-surface--background);
		box-shadow: var(--shadow-overlay);
	}
	.mobile-nav__panel :global(.sidebar) {
		display: flex;
		width: 100%;
		min-height: 100%;
		border: 0;
	}
</style>
