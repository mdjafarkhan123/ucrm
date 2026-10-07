<script lang="ts">
	import { onMount } from 'svelte';
	import type { Snippet } from 'svelte';
	import { DropdownMenu } from 'bits-ui';
	import moonIcon from '@tabler/icons/outline/moon.svg?raw';
	import sunIcon from '@tabler/icons/outline/sun.svg?raw';
	import menuIcon from '@tabler/icons/outline/menu-2.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import logoutIcon from '@tabler/icons/outline/logout.svg?raw';
	import { resolve } from '$app/paths';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import photoIcon from '@tabler/icons/outline/user-circle.svg?raw';
	import searchIcon from '@tabler/icons/outline/search.svg?raw';

	let {
		onmenutoggle,
		onSearchOpen,
		searchPlaceholder = 'Search',
		accountLabel,
		notifications,
		account = null,
		avatar = null,
		onEditPhoto,
		showSecurityLink = false,
		isSigningOut = false,
		signOutError = '',
		onSignOut
	}: {
		onmenutoggle?: () => void;
		onSearchOpen?: () => void;
		searchPlaceholder?: string;
		accountLabel: string;
		notifications?: Snippet;
		account?: { name: string | null; email: string | null; role: string } | null;
		/** The signed-in person's own avatar, drawn in place of the generic account icon. */
		avatar?: { id: string; url: string | null; name: string | null } | null;
		/** Opens the profile photo dialog from the account menu. */
		onEditPhoto?: () => void;
		showSecurityLink?: boolean;
		isSigningOut?: boolean;
		signOutError?: string;
		onSignOut?: () => void;
	} = $props();

	let isDark = $state(false);

	onMount(() => {
		const savedTheme = localStorage.getItem('ucrm-theme');
		isDark =
			savedTheme === 'dark' ||
			(savedTheme === null && matchMedia('(prefers-color-scheme: dark)').matches);
		applyTheme(isDark);
	});

	function applyTheme(dark: boolean) {
		document.documentElement.toggleAttribute('data-theme', dark);
		if (dark) document.documentElement.dataset.theme = 'dark';
	}

	function toggleTheme() {
		isDark = !isDark;
		localStorage.setItem('ucrm-theme', isDark ? 'dark' : 'light');
		applyTheme(isDark);
	}

	function accountRoleLabel(role: string) {
		return role === 'admin' ? 'Administrator' : `${role[0].toUpperCase()}${role.slice(1)}`;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<header class="topbar">
	<button class="topbar__menu" type="button" aria-label="Open navigation" onclick={onmenutoggle}>
		<span aria-hidden="true">{@html menuIcon}</span>
	</button>

	<div class="topbar__search">
		{#if onSearchOpen}
			<button class="topbar__search-trigger" type="button" onclick={onSearchOpen}>
				<span class="topbar__search-icon" aria-hidden="true">{@html searchIcon}</span>
				<span class="topbar__search-label">{searchPlaceholder}</span>
				<kbd aria-hidden="true">Ctrl K</kbd>
			</button>
		{:else}
			<div class="topbar__search-placeholder" aria-hidden="true">
				<span class="topbar__search-icon">{@html searchIcon}</span>
				<span>{searchPlaceholder}</span>
			</div>
		{/if}
	</div>

	<DropdownMenu.Root>
		<DropdownMenu.Trigger class="topbar__add">
			<span aria-hidden="true">{@html plusIcon}</span><span class="topbar__add-label">Add New</span>
		</DropdownMenu.Trigger>
		<DropdownMenu.Portal disabled>
			<DropdownMenu.Content class="topbar__menu-panel" align="start" sideOffset={8}>
				<p class="topbar__menu-empty">Nothing to create yet</p>
			</DropdownMenu.Content>
		</DropdownMenu.Portal>
	</DropdownMenu.Root>

	<div class="topbar__spacer"></div>

	<button
		class="topbar__icon-btn"
		type="button"
		aria-label={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
		aria-pressed={isDark}
		title={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
		onclick={toggleTheme}
	>
		<span aria-hidden="true">{@html isDark ? sunIcon : moonIcon}</span>
	</button>

	{#if notifications}{@render notifications()}{/if}

	<DropdownMenu.Root>
		<DropdownMenu.Trigger class="topbar__account" aria-label={`Account menu for ${accountLabel}`}>
			{#if avatar}
				<span class="topbar__avatar" aria-hidden="true">
					<Avatar id={avatar.id} name={avatar.name} src={avatar.url} size="medium" />
				</span>
			{:else}
				<span class="topbar__avatar" aria-hidden="true">{@html userIcon}</span>
			{/if}
		</DropdownMenu.Trigger>
		<DropdownMenu.Portal disabled>
			<DropdownMenu.Content class="topbar__menu-panel" align="end" sideOffset={8}>
				<p class="topbar__menu-heading">{accountLabel}</p>
				{#if account}
					<div class="topbar__account-summary">
						<div class="topbar__account-identity">
							<strong>{account.name ?? 'Name not set'}</strong>
							<Badge size="base">{accountRoleLabel(account.role)}</Badge>
						</div>
						{#if account.email}<span>{account.email}</span>{/if}
					</div>
				{/if}
				{#if onEditPhoto}
					<DropdownMenu.Item class="topbar__menu-item" onSelect={onEditPhoto}>
						<span aria-hidden="true">{@html photoIcon}</span>
						Profile photo
					</DropdownMenu.Item>
				{/if}
				{#if showSecurityLink}
					<a class="topbar__menu-item" href={resolve('/settings/security')}>Password and security</a
					>
				{/if}
				{#if onSignOut}
					<button
						class="topbar__menu-item"
						type="button"
						onclick={onSignOut}
						disabled={isSigningOut}
					>
						<span aria-hidden="true">{@html logoutIcon}</span>
						{isSigningOut ? 'Signing out…' : 'Sign out'}
					</button>
				{/if}
				{#if signOutError}<span class="topbar__sign-out-error" role="alert">{signOutError}</span
					>{/if}
			</DropdownMenu.Content>
		</DropdownMenu.Portal>
	</DropdownMenu.Root>
</header>

<!-- eslint-enable svelte/no-at-html-tags -->

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
	.topbar__search {
		flex: 1 1 320px;
		min-width: 0;
		max-width: 420px;
	}
	.topbar__search-trigger,
	.topbar__search-placeholder {
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
	.topbar__search-trigger {
		cursor: pointer;
		transition:
			background var(--timing-quick),
			box-shadow var(--timing-quick);
	}
	.topbar__search-trigger:hover {
		background: var(--color-surface--hover);
	}
	.topbar__search-trigger:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	.topbar__search-placeholder {
		border-color: var(--color-border);
		background: var(--color-disabled--secondary);
	}
	.topbar__search-icon,
	.topbar__search-icon :global(svg) {
		display: block;
		flex: 0 0 auto;
		width: 18px;
		height: 18px;
	}
	.topbar__search-label {
		flex: 1;
	}
	.topbar__search-trigger kbd {
		padding: var(--space-smallest) var(--space-smaller);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-small);
		color: var(--color-text--secondary);
		background: var(--color-surface--background);
		font: inherit;
		font-size: var(--typography--fontSize-small);
		line-height: 1;
	}
	.topbar__spacer {
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
	:global(.topbar__menu-panel) {
		z-index: var(--elevation-menu);
		min-width: 176px;
		padding: var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}
	:global(.topbar__menu-empty) {
		padding: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	:global(.topbar__menu-heading) {
		padding: var(--space-small) var(--space-small) var(--space-slim);
		margin-bottom: var(--space-small);
		border-bottom: var(--border-base) solid var(--color-border);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	:global(.topbar__account-summary) {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		padding: var(--space-small) var(--space-small) var(--space-slim);
		margin-bottom: var(--space-small);
		border-bottom: var(--border-base) solid var(--color-border);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		overflow: hidden;
	}
	:global(.topbar__account-summary strong) {
		color: var(--color-heading);
		font-weight: 600;
	}
	:global(.topbar__account-identity) {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		min-width: 0;
	}
	:global(.topbar__account-identity .badge) {
		flex: 0 0 auto;
	}
	:global(.topbar__account-summary strong),
	:global(.topbar__account-summary span) {
		text-overflow: ellipsis;
		overflow: hidden;
		white-space: nowrap;
	}
	:global(.topbar__menu-item) {
		display: flex;
		width: 100%;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-small);
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-heading);
		background: transparent;
		font-size: var(--typography--fontSize-small);
		text-align: left;
		text-decoration: none;
		cursor: pointer;
	}
	:global(.topbar__menu-item:hover) {
		background: var(--color-surface--hover);
	}
	:global(.topbar__menu-item:focus-visible) {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	:global(.topbar__sign-out-error) {
		display: block;
		padding: 0 var(--space-small) var(--space-small);
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.topbar__menu {
		display: none;
		flex: 0 0 auto;
		padding: var(--space-small);
		border: 0;
		border-radius: var(--radius-small);
		color: var(--color-icon);
		background: transparent;
		font-size: var(--typography--fontSize-largest);
	}
	.topbar__menu span,
	.topbar__menu span :global(svg) {
		display: inline-flex;
		width: 20px;
		height: 20px;
	}
	.topbar__menu:hover {
		background: var(--color-surface--hover);
	}
	.topbar__menu:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	@media (max-width: 767px) {
		.topbar {
			flex-wrap: wrap;
			padding-inline: var(--space-base);
		}
		.topbar__menu {
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
		.topbar__search {
			display: none;
		}
	}
</style>
