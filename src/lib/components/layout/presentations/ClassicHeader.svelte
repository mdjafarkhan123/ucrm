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
	.topbar {
		display: flex;
		align-items: center;
		gap: 10px;
		min-height: 64px;
		padding: 0 12px 0 4px;
		color: var(--classic2-ink);
	}
	:global(.topbar__search) {
		flex: 1 1 440px;
		min-width: 0;
		max-width: 440px;
		container-type: inline-size;
	}
	:global(.topbar__search-trigger),
	:global(.topbar__search-placeholder) {
		display: flex;
		align-items: center;
		gap: 10px;
		width: 100%;
		min-height: 44px;
		padding: 0 14px;
		border: 1px solid var(--classic2-border-control);
		border-radius: 14px;
		background: var(--classic2-surface);
		color: var(--classic2-muted);
		font: inherit;
		font-size: 14px;
		font-weight: 500;
		text-align: left;
	}
	:global(.topbar__search-trigger) {
		cursor: pointer;
	}
	:global(.topbar__search-trigger:hover) {
		border-color: var(--classic2-green);
	}
	:global(.topbar__search-label) {
		flex: 1;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	:global(.topbar__search-icon),
	:global(.topbar__search-icon svg) {
		display: block;
		flex: 0 0 18px;
		width: 18px;
		height: 18px;
	}
	:global(.topbar__search-trigger kbd) {
		flex: 0 0 auto;
		padding: 4px 6px;
		border-radius: 8px;
		background: var(--classic2-chip);
		color: var(--classic2-muted);
		font: inherit;
		font-size: 11px;
	}
	:global(
		:root[data-theme='dark']:has(.app-shell[data-presentation='classic'])
			.topbar__search-trigger
			kbd
	) {
		color: var(--classic2-body);
	}
	:global(.topbar__spacer) {
		flex: 1;
	}
	:global(.topbar__add) {
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		gap: 8px;
		min-height: 44px;
		padding: 0 16px;
		border: 1px solid var(--classic2-solid-green);
		border-radius: 14px;
		background: var(--classic2-solid-green);
		color: var(--classic2-green-on);
		font: inherit;
		font-size: 14px;
		font-weight: 700;
		white-space: nowrap;
		cursor: pointer;
	}
	:global(.topbar__add:hover) {
		background: var(--classic2-green-hover);
	}
	:global(.topbar__add span:first-child),
	:global(.topbar__add svg) {
		display: inline-flex;
		width: 18px;
		height: 18px;
	}
	:global(.topbar__icon-btn),
	:global(.app-shell[data-presentation='classic'] .notification-bell__trigger) {
		display: inline-grid;
		flex: 0 0 44px;
		width: 44px;
		height: 44px;
		place-items: center;
		padding: 0;
		border: 1px solid var(--classic2-border-control);
		border-radius: 14px;
		background: var(--classic2-surface);
		color: var(--classic2-body);
		cursor: pointer;
	}
	:global(.topbar__icon-btn:hover),
	:global(.app-shell[data-presentation='classic'] .notification-bell__trigger:hover) {
		border-color: var(--classic2-green);
	}
	:global(.topbar__icon-btn span),
	:global(.topbar__icon-btn svg) {
		display: block;
		width: 20px;
		height: 20px;
	}
	:global(.topbar__account) {
		display: inline-grid;
		flex: 0 0 44px;
		width: 44px;
		height: 44px;
		place-items: center;
		overflow: hidden;
		padding: 0;
		border: 0;
		border-radius: 50%;
		background: linear-gradient(145deg, var(--classic2-solid-green), var(--classic2-feature-end));
		color: #fff;
		font: inherit;
		font-size: 14px;
		font-weight: 700;
		cursor: pointer;
	}
	:global(.topbar__account:hover) {
		box-shadow: 0 0 0 3px var(--classic2-green-soft);
	}
	:global(.topbar__avatar),
	:global(.topbar__avatar .avatar) {
		display: grid;
		width: 100%;
		height: 100%;
		place-items: center;
	}
	:global(.app-shell[data-presentation='classic'] .topbar__avatar .avatar) {
		--avatar-bg: linear-gradient(145deg, var(--classic2-solid-green), var(--classic2-feature-end));
		--avatar-fg: var(--classic2-white);
	}
	:global(.topbar__avatar-icon) {
		display: none;
	}
	:global(.topbar__avatar-initials) {
		display: block;
	}
	:global(.topbar__avatar svg) {
		width: 20px;
		height: 20px;
	}
	:global(.topbar__menu) {
		display: none;
		flex: 0 0 44px;
		width: 44px;
		height: 44px;
		place-items: center;
		padding: 0;
		border: 1px solid var(--classic2-border-control);
		border-radius: 14px;
		background: var(--classic2-surface);
		color: var(--classic2-body);
	}
	:global(.topbar__menu svg) {
		width: 20px;
		height: 20px;
	}
	:global(.topbar__search-trigger:focus-visible),
	:global(.topbar__icon-btn:focus-visible),
	:global(.app-shell[data-presentation='classic'] .notification-bell__trigger:focus-visible),
	:global(.topbar__add:focus-visible),
	:global(.topbar__account:focus-visible),
	:global(.topbar__menu:focus-visible) {
		outline: 3px solid var(--classic2-green);
		outline-offset: 2px;
	}
	@container (max-width: 165px) {
		:global(.topbar__search-label),
		:global(.topbar__search-trigger kbd) {
			display: none;
		}
		:global(.topbar__search-trigger) {
			justify-content: center;
		}
	}
	@media (max-width: 767px) {
		.topbar {
			flex-wrap: wrap;
			padding: 0;
		}
		:global(.topbar__menu) {
			display: inline-grid;
		}
		:global(.topbar__search) {
			order: 5;
			flex-basis: 100%;
			max-width: none;
		}
		:global(.topbar__spacer) {
			flex: 1;
		}
		:global(.topbar__add-label) {
			display: none;
		}
		:global(.topbar__add) {
			width: 44px;
			padding: 0;
		}
	}
	@media (max-width: 390px) {
		:global(.topbar__icon-btn),
		:global(.notification-bell__trigger),
		:global(.topbar__add),
		:global(.topbar__account),
		:global(.topbar__menu) {
			width: 40px;
			height: 40px;
			flex-basis: 40px;
		}
	}
</style>
