<script lang="ts">
	import { onMount } from 'svelte';
	import type { Snippet } from 'svelte';
	import type { HeaderFrame } from './presentations/header-types';
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
		Header,
		identity,
		onmenutoggle,
		onSearchOpen,
		searchPlaceholder = 'Search',
		accountLabel,
		notifications,
		timer,
		account = null,
		avatar = null,
		onEditPhoto,
		showSecurityLink = false,
		isSigningOut = false,
		signOutError = '',
		onSignOut
	}: {
		Header: HeaderFrame;
		identity?: Snippet;
		onmenutoggle?: () => void;
		onSearchOpen?: () => void;
		searchPlaceholder?: string;
		accountLabel: string;
		notifications?: Snippet;
		/** The signed-in person's running timer, shown by every presentation's header. */
		timer?: Snippet;
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
<Header {identity} {notifications} {timer}>
	{#snippet menu()}
		<button class="topbar__menu" type="button" aria-label="Open navigation" onclick={onmenutoggle}>
			<span aria-hidden="true">{@html menuIcon}</span>
		</button>
	{/snippet}
	{#snippet search()}
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
	{/snippet}
	{#snippet add()}
		<DropdownMenu.Root>
			<DropdownMenu.Trigger class="topbar__add">
				<span aria-hidden="true">{@html plusIcon}</span><span class="topbar__add-label"
					>Add New</span
				>
			</DropdownMenu.Trigger>
			<DropdownMenu.Portal disabled>
				<DropdownMenu.Content class="topbar__menu-panel" align="start" sideOffset={8}>
					<p class="topbar__menu-empty">Nothing to create yet</p>
				</DropdownMenu.Content>
			</DropdownMenu.Portal>
		</DropdownMenu.Root>
	{/snippet}
	{#snippet appearance()}
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
	{/snippet}
	{#snippet accountControl()}
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
						<a class="topbar__menu-item" href={resolve('/settings/security')}
							>Password and security</a
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
	{/snippet}
</Header>

<!-- eslint-enable svelte/no-at-html-tags -->
<style lang="scss">
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
</style>
