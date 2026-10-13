<svelte:options css="injected" />

<script lang="ts">
	import Header from './ClassicHeader.svelte';
	import Sidebar from '../Sidebar.svelte';
	import MobileNav from '../MobileNav.svelte';
	import type { ShellFrameProps } from './types';
	let {
		notice,
		children,
		header,
		groups,
		brand,
		eyebrow,
		logoUrl,
		variant,
		mobileOpen = $bindable(false),
		sidebarCollapsed = $bindable(false)
	}: ShellFrameProps = $props();
</script>

<div
	class={`app-shell app-shell--${variant}`}
	data-presentation="classic"
	style={`--shell-nav-width: ${sidebarCollapsed ? '76px' : '256px'}`}
>
	<Sidebar {groups} {brand} {eyebrow} {logoUrl} bind:collapsed={sidebarCollapsed} />
	<div class="app-shell__body">
		{@render header(Header)}
		{@render notice?.()}
		<div class="app-shell__main scroll-y-auto">{@render children()}</div>
	</div>
	<MobileNav bind:open={mobileOpen} {groups} {brand} {eyebrow} {logoUrl} />
</div>

<style lang="scss">
	@use '../../../styles/classic-theme-tokens' as classic;

	/* The root also owns Bits UI portals (menus and dialogs). The Classic shell must be present so a
	 * later switch to Botanical cannot leave these tokens active after this stylesheet has loaded. */
	:global(:root:has(.app-shell[data-presentation='classic'])) {
		@include classic.light;
	}

	:global(:root[data-theme='dark']:has(.app-shell[data-presentation='classic'])) {
		@include classic.dark;
	}

	/* Where the content column starts and ends, so anything pinned over the page — the action bar at the
	 * bottom of a form or detail page — can line up with the page underneath it. `--shell-nav-width` is set
	 * on the element itself, because only this component knows whether the sidebar is collapsed. */
	.app-shell {
		--shell-edge: var(--space-slim);
		--shell-content-left: calc(
			var(--shell-edge) + var(--shell-nav-width, 256px) + var(--space-large)
		);
		--shell-content-right: calc(var(--shell-edge) + var(--space-large));

		position: relative;
		display: flex;
		height: 100dvh;
		/* `clip`, not `hidden`: a `hidden` box is still a scroll container, so a step's scrollIntoView
		 * (or focus, or a #link) could slide the whole frame up and push the top bar off screen. Only
		 * `.app-shell__main` and the panels inside it scroll. */
		overflow: clip;
		background: var(--color-surface--background);
		padding: var(--shell-edge);
		gap: var(--space-base);
	}
	.app-shell__body {
		display: flex;
		flex: 1;
		min-width: 0;
		min-height: 0;
		flex-direction: column;
		overflow: clip;
	}
	.app-shell__main {
		flex: 1;
		min-height: 0;
		padding-block: var(--space-base) 0;
	}
	/* The sidebar is hidden here, so the content column runs the full width inside the shell padding. */
	@media (max-width: 767px) {
		.app-shell {
			--shell-edge: var(--space-base);
			--shell-content-left: var(--shell-edge);
			--shell-content-right: calc(var(--shell-edge) + var(--space-base));

			gap: var(--space-base);
		}
		.app-shell__main {
			padding: var(--space-base) var(--space-base) var(--space-base) 0;
		}
	}
</style>
