<svelte:options css="injected" />

<script lang="ts">
	import type { HeaderFrameProps } from './header-types';
	let {
		identity,
		menu,
		search,
		add,
		timer,
		appearance,
		notifications,
		accountControl
	}: HeaderFrameProps = $props();
</script>

<header class="topbar" data-shell-header>
	{@render menu()}
	{@render identity?.()}
	{@render search()}
	<div class="topbar__spacer"></div>
	{@render timer?.()}
	{@render appearance()}
	{@render notifications?.()}
	{@render add()}
	{@render accountControl()}
</header>

<style lang="scss">
	/* No card of its own: the controls sit straight on the page, 44px high, in line with the page below. */
	.topbar {
		display: flex;
		align-items: center;
		gap: 10px;
		min-height: 44px;
		padding: var(--space-small) var(--space-slim) 0 var(--space-smaller);
	}
	.topbar :global(.notification-bell__trigger) {
		width: 44px;
		height: 44px;
	}
	:global(.topbar__search) {
		flex: 1 1 320px;
		min-width: 0;
		max-width: 440px;
		container-type: inline-size;
	}
	// Squeezed by the header's other controls (a running timer beside the sidebar on a small laptop), the
	// search box shows only its magnifier rather than a clipped word. The label stays for screen readers.
	@container (max-width: 140px) {
		:global(.topbar__search-trigger),
		:global(.topbar__search-placeholder) {
			justify-content: center;
			padding: 0;
		}
		:global(.topbar__search-trigger kbd) {
			display: none;
		}
		:global(.topbar__search-label),
		:global(.topbar__search-placeholder span:not(.topbar__search-icon)) {
			position: absolute;
			width: 1px;
			height: 1px;
			margin: -1px;
			overflow: hidden;
			clip: rect(0 0 0 0);
			white-space: nowrap;
		}
	}
	:global(.topbar__search-trigger),
	:global(.topbar__search-placeholder) {
		display: flex;
		width: 100%;
		min-height: 44px;
		align-items: center;
		gap: 10px;
		padding: 0 var(--space-small) 0 14px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-text--secondary);
		background: var(--color-surface);
		font: inherit;
		text-align: left;
	}
	:global(.topbar__search-trigger) {
		cursor: pointer;
		transition:
			background var(--timing-quick),
			box-shadow var(--timing-quick);
	}
	:global(.topbar__search-trigger):hover {
		background: var(--color-surface--hover);
	}
	:global(.topbar__search-trigger):focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	:global(.topbar__search-placeholder) {
		border-color: var(--color-border);
		background: var(--color-disabled--secondary);
	}
	:global(.topbar__search-icon),
	:global(.topbar__search-icon) :global(svg) {
		display: block;
		flex: 0 0 auto;
		width: 18px;
		height: 18px;
		color: var(--color-icon--secondary);
	}
	:global(.topbar__search-label) {
		flex: 1;
		font-weight: 500;
	}
	:global(.topbar__search-trigger kbd) {
		padding: 3px 7px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-text--secondary);
		background: var(--color-surface--background--subtle);
		font: inherit;
		font-size: var(--typography--fontSize-overline);
		font-weight: 600;
		line-height: 1.2;
	}
	:global(.topbar__spacer) {
		flex: 1;
	}
	:global(.topbar__account) {
		display: inline-grid;
		flex: 0 0 auto;
		width: 44px;
		height: 44px;
		place-items: center;
		padding: 0;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-icon);
		background: var(--color-surface);
		transition: all var(--timing-base) ease-out;
	}
	:global(.topbar__account:hover) {
		border-color: var(--color-border--interactive);
		color: var(--color-interactive--subtle--hover);
		background: var(--color-surface--hover);
	}
	:global(.topbar__account:focus-visible) {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	:global(.topbar__account) {
		border-color: var(--color-interactive);
		border-radius: var(--radius-circle);
		overflow: hidden;
		background: var(--color-interactive);
	}
	:global(.topbar__account:hover) {
		border-color: var(--color-interactive--hover);
		background: var(--color-interactive--hover);
	}
	:global(.topbar__avatar) {
		display: grid;
		width: 100%;
		height: 100%;
		place-items: center;
		color: var(--color-surface);
		background: var(--color-interactive);
	}
	// The person's own avatar fills the whole round button, border to border. Without a photo it shows
	// bold initials on the brand green.
	:global(.topbar__avatar .avatar) {
		--avatar-bg: var(--color-interactive);
		--avatar-fg: var(--color-surface);
		width: 100%;
		height: 100%;
		font-size: var(--typography--fontSize-base);
		font-weight: 700;
	}
	:global(.topbar__avatar svg) {
		width: 20px;
		height: 20px;
	}
	// The navigation button shows only where the sidebar folds away.
	.topbar :global(.topbar__menu.button) {
		display: none;
	}
	@media (max-width: 767px) {
		.topbar {
			flex-wrap: wrap;
			padding-inline: var(--space-base);
		}
		.topbar :global(.topbar__menu.button) {
			display: inline-flex;
		}
	}
	@media (max-width: 639px) {
		:global(.topbar__add-label) {
			display: none;
		}
	}
	@media (max-width: 489px) {
		:global(.topbar__search) {
			display: none;
		}
	}
</style>
