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
	{@render add()}
	<div class="topbar__spacer"></div>
	{@render timer?.()}
	{@render appearance()}
	{@render notifications?.()}
	{@render accountControl()}
</header>

<style lang="scss">
	.topbar {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		min-height: 62px;
		padding: var(--space-slim) var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}
	:global(.topbar__search) {
		flex: 1 1 320px;
		min-width: 0;
		max-width: 420px;
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
		min-height: 40px;
		align-items: center;
		gap: var(--space-small);
		padding: 0 var(--space-small);
		border: var(--border-base) solid var(--color-border--interactive);
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
	}
	:global(.topbar__search-label) {
		flex: 1;
	}
	:global(.topbar__search-trigger kbd) {
		padding: var(--space-smallest) var(--space-smaller);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-small);
		color: var(--color-text--secondary);
		background: var(--color-surface--background);
		font: inherit;
		font-size: var(--typography--fontSize-small);
		line-height: 1;
	}
	:global(.topbar__spacer) {
		flex: 1;
	}
	:global(.topbar__add) {
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		gap: var(--space-smaller);
		min-height: 40px;
		padding: 0 var(--space-base);
		border: var(--border-base) solid var(--color-interactive);
		border-radius: var(--radius-base);
		color: var(--color-surface);
		background: var(--color-interactive);
		font-weight: 600;
		white-space: nowrap;
		transition: all var(--timing-base) ease-out;
	}
	:global(.topbar__add:hover) {
		background: var(--color-interactive--hover);
	}
	:global(.topbar__add:focus-visible) {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	:global(.topbar__add span:first-child),
	:global(.topbar__add span:first-child svg) {
		display: inline-flex;
		width: 18px;
		height: 18px;
	}
	:global(.topbar__icon-btn),
	:global(.topbar__account) {
		display: inline-grid;
		flex: 0 0 auto;
		width: 40px;
		height: 40px;
		place-items: center;
		padding: 0;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-icon);
		background: var(--color-surface);
		transition: all var(--timing-base) ease-out;
	}
	:global(.topbar__icon-btn:hover),
	:global(.topbar__account:hover) {
		border-color: var(--color-border--interactive);
		color: var(--color-interactive--subtle--hover);
		background: var(--color-surface--hover);
	}
	:global(.topbar__icon-btn:focus-visible),
	:global(.topbar__account:focus-visible) {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	:global(.topbar__icon-btn:disabled),
	:global(.topbar__icon-btn[aria-disabled='true']) {
		color: var(--color-disabled);
		cursor: not-allowed;
	}
	:global(.topbar__icon-btn span),
	:global(.topbar__icon-btn span svg) {
		display: inline-flex;
		width: 20px;
		height: 20px;
	}
	:global(.topbar__account) {
		border-radius: var(--radius-circle);
		overflow: hidden;
	}
	:global(.topbar__avatar) {
		display: grid;
		width: 100%;
		height: 100%;
		place-items: center;
		color: var(--color-brand);
		background: var(--color-surface--active);
	}
	// The person's own avatar fills the whole round button, border to border.
	:global(.topbar__avatar .avatar) {
		width: 100%;
		height: 100%;
	}
	:global(.topbar__avatar svg) {
		width: 20px;
		height: 20px;
	}
	:global(.topbar__menu) {
		display: none;
		flex: 0 0 auto;
		padding: var(--space-small);
		border: 0;
		border-radius: var(--radius-small);
		color: var(--color-icon);
		background: transparent;
		font-size: var(--typography--fontSize-largest);
	}
	:global(.topbar__menu span),
	:global(.topbar__menu span svg) {
		display: inline-flex;
		width: 20px;
		height: 20px;
	}
	:global(.topbar__menu):hover {
		background: var(--color-surface--hover);
	}
	:global(.topbar__menu):focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	@media (max-width: 767px) {
		.topbar {
			flex-wrap: wrap;
			padding-inline: var(--space-base);
		}
		:global(.topbar__menu) {
			display: inline-grid;
			place-items: center;
		}
	}
	@media (max-width: 639px) {
		:global(.topbar__add-label) {
			display: none;
		}
		:global(.topbar__add) {
			padding: 0 var(--space-small);
		}
	}
	@media (max-width: 489px) {
		:global(.topbar__search) {
			display: none;
		}
	}
</style>
