<script lang="ts">
	import Sidebar, { type NavItem } from './Sidebar.svelte';
	import Topbar from './Topbar.svelte';
	import MobileNav from './MobileNav.svelte';
	import NotificationBell from '$lib/components/jafar/NotificationBell.svelte';
	import { goto } from '$app/navigation';
	import { invalidateAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';

	import logoutIcon from '@tabler/icons/outline/logout.svg?raw';

let {
		children,
		variant = 'contractor'
	}: { children: import('svelte').Snippet; variant?: 'contractor' | 'owner' } = $props();
	let mobileOpen = $state(false);
	let signOutError = $state('');

	const contractorItems: NavItem[] = [
		{ label: 'Dashboard', href: '/dashboard', icon: 'dashboard' },
		{ label: 'Clients', href: '/clients', icon: 'users' },
		{ label: 'Requests', href: '/requests', icon: 'inbox' },
		{ label: 'Quotes', href: '/quotes', icon: 'fileInvoice' },
		{ label: 'Jobs', href: '/jobs', icon: 'tools' },
		{ label: 'Schedule', href: '/schedule', icon: 'calendar' },
		{ label: 'Invoices', href: '/invoices', icon: 'receipt' },
		{ label: 'Inbox', href: '/inbox', icon: 'messages' }
	];
	const ownerItems: NavItem[] = [
		{ label: 'Overview', href: '/jafar', icon: 'dashboard' },
		{ label: 'Prospects', href: '/jafar/prospects', icon: 'users' },
		{ label: 'Packages', href: '/jafar/packages', icon: 'package' },
		{ label: 'Organizations', href: '/jafar/organizations', icon: 'building' },
		{ label: 'Operations', href: '/jafar/operations', icon: 'alertTriangle' },
		{ label: 'Templates', href: '/jafar/message-templates', icon: 'mail' },
		{ label: 'Settings', href: '/jafar/settings', icon: 'settings' }
	];
	const items = $derived(variant === 'owner' ? ownerItems : contractorItems);
	const brand = $derived(variant === 'owner' ? 'Control Room' : 'Contractor CRM');
	const eyebrow = $derived(variant === 'owner' ? 'Platform owner' : 'Workspace');
	const ownerTitle = $derived(
		page.url.pathname.startsWith('/jafar/organizations')
			? 'Organizations'
			: page.url.pathname.startsWith('/jafar/prospects')
				? 'Prospects'
				: page.url.pathname.startsWith('/jafar/packages')
					? 'Packages'
					: page.url.pathname.startsWith('/jafar/operations')
						? 'Operations'
						: page.url.pathname.startsWith('/jafar/message-templates')
							? 'Templates'
							: page.url.pathname.startsWith('/jafar/settings')
								? 'Settings'
								: page.url.pathname.startsWith('/jafar/notifications')
									? 'Notifications'
									: 'Platform overview'
	);
	const title = $derived(variant === 'owner' ? ownerTitle : 'Contractor workspace');
	let isSigningOut = $state(false);

	async function signOut() {
		isSigningOut = true;
		signOutError = '';
		try {
			const response = await fetch(
				variant === 'owner' ? '/api/jafar/session' : '/api/auth/session',
				{ method: 'DELETE' }
			);
			if (!response.ok) throw new Error('Sign out request failed.');

			if (variant === 'owner') {
				await invalidateAll();
			} else {
				await goto(resolve('/login'));
			}
		} catch (error) {
			console.error('Could not sign out.', error);
			signOutError = 'Could not sign out. Please try again.';
		} finally {
			isSigningOut = false;
		}
	}
</script>

<div class={`app-shell app-shell--${variant}`}>
	<Sidebar {items} {brand} {eyebrow} />
	<div class="app-shell__body">
		<Topbar {eyebrow} {title} onmenutoggle={() => (mobileOpen = true)}>
			{#if variant === 'contractor'}
				<a class="app-shell__security" href={resolve('/settings/security')}>Security</a>
			{:else}
				<NotificationBell />
			{/if}
			<button
				class="app-shell__sign-out"
				type="button"
				onclick={() => void signOut()}
				disabled={isSigningOut}
			>
				<span aria-hidden="true">{@html logoutIcon}</span>
				{isSigningOut ? 'Signing out…' : 'Sign out'}
			</button>
			{#if signOutError}<span class="app-shell__sign-out-error" role="alert">{signOutError}</span>{/if}
		</Topbar>
		<div class="app-shell__main">{@render children()}</div>
	</div>
	<MobileNav bind:open={mobileOpen} {items} {brand} {eyebrow} />
</div>

<style lang="scss">
	.app-shell {
		position: relative;
		display: flex;
		min-height: 100vh;
		background: var(--color-surface--background);
		padding: var(--space-large);
		gap: var(--space-large);
	}
	.app-shell__body {
		display: flex;
		flex: 1;
		min-width: 0;
		flex-direction: column;
	}
	.app-shell__main {
		flex: 1;
		padding: var(--space-large);
	}
	.app-shell__sign-out {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
		min-height: 36px;
		padding: 0 var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-heading);
		background: var(--color-surface);
	}
	.app-shell__sign-out > span,
	.app-shell__sign-out > span :global(svg) {
		display: inline-flex;
		width: 18px;
		height: 18px;
	}
	.app-shell__security {
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		text-decoration: underline;
		text-underline-offset: var(--space-smaller);
	}
	.app-shell__security:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	.app-shell__sign-out:hover:not(:disabled) {
		background: var(--color-surface--hover);
	}
	.app-shell__sign-out-error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.app-shell__sign-out:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	.app-shell__sign-out:disabled {
		color: var(--color-disabled);
		cursor: not-allowed;
	}
	@media (max-width: 767px) {
		.app-shell {
			padding: var(--space-base);
			gap: var(--space-base);
		}
		.app-shell__main {
			padding: var(--space-base);
		}
	}
</style>
