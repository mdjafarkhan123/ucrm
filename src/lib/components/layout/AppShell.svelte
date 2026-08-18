<script lang="ts">
	import Sidebar, { type NavGroup } from './Sidebar.svelte';
	import Topbar from './Topbar.svelte';
	import MobileNav from './MobileNav.svelte';
	import NotificationBell from '$lib/components/jafar/NotificationBell.svelte';
	import { goto } from '$app/navigation';
	import { invalidateAll } from '$app/navigation';
	import { resolve } from '$app/paths';

	import bellIcon from '@tabler/icons/outline/bell.svg?raw';
	import logoutIcon from '@tabler/icons/outline/logout.svg?raw';

	let {
		children,
		variant = 'contractor'
	}: { children: import('svelte').Snippet; variant?: 'contractor' | 'owner' } = $props();
	let mobileOpen = $state(false);
	let sidebarCollapsed = $state(false);
	let signOutError = $state('');

	const contractorGroups: NavGroup[] = [
		{
			label: 'Overview',
			items: [
				{ label: 'Dashboard', href: '/dashboard', icon: 'dashboard' },
				{ label: 'Schedule', href: '/schedule', icon: 'calendar', unavailable: true }
			]
		},
		{
			label: 'Customers',
			items: [
				{ label: 'Inbox', href: '/inbox', icon: 'inbox', unavailable: true },
				{ label: 'Clients', href: '/clients', icon: 'users' },
				{ label: 'Requests', href: '/requests', icon: 'route' },
				{ label: 'Pipeline', href: '/pipeline', icon: 'chartBar', unavailable: true }
			]
		},
		{
			label: 'Work & Money',
			items: [
				{ label: 'Jobs', href: '/jobs', icon: 'tools', unavailable: true },
				{ label: 'Quotes', href: '/quotes', icon: 'fileInvoice', unavailable: true },
				{ label: 'Invoices', href: '/invoices', icon: 'receipt', unavailable: true }
			]
		},
		{
			label: 'Growth',
			items: [
				{ label: 'Reputation', href: '/reputation', icon: 'star', unavailable: true },
				{ label: 'Growth Feed', href: '/growth', icon: 'trendingUp', unavailable: true }
			]
		},
		{
			label: 'System',
			items: [
				{ label: 'Settings', href: '/settings', icon: 'settings', unavailable: true },
				{ label: 'Team', href: '/team', icon: 'usersGroup', unavailable: true },
				{ label: 'Notifications', href: '/notifications', icon: 'mail', unavailable: true },
				{ label: 'Usage', href: '/usage', icon: 'chartBar', unavailable: true }
			]
		}
	];
	const ownerGroups: NavGroup[] = [
		{
			items: [
				{ label: 'Overview', href: '/jafar', icon: 'dashboard' },
				{ label: 'Prospects', href: '/jafar/prospects', icon: 'users' },
				{ label: 'Packages', href: '/jafar/packages', icon: 'package' },
				{ label: 'Organizations', href: '/jafar/organizations', icon: 'building' },
				{ label: 'Operations', href: '/jafar/operations', icon: 'alertTriangle' },
				{ label: 'Templates', href: '/jafar/message-templates', icon: 'mail' },
				{ label: 'Settings', href: '/jafar/settings', icon: 'settings' }
			]
		}
	];
	const groups = $derived(variant === 'owner' ? ownerGroups : contractorGroups);
	const brand = $derived(variant === 'owner' ? 'Control Room' : 'Contractor CRM');
	const eyebrow = $derived(variant === 'owner' ? 'Platform owner' : 'Workspace');
	const accountLabel = $derived(variant === 'owner' ? 'Platform owner' : 'Your account');
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

<!-- eslint-disable svelte/no-at-html-tags -->
<div
	class={`app-shell app-shell--${variant}`}
	style={`--shell-nav-width: ${sidebarCollapsed ? '76px' : '256px'}`}
>
	<Sidebar {groups} {brand} {eyebrow} bind:collapsed={sidebarCollapsed} />
	<div class="app-shell__body">
		<Topbar {accountLabel} onmenutoggle={() => (mobileOpen = true)}>
			{#snippet notifications()}
				{#if variant === 'owner'}
					<NotificationBell />
				{:else}
					<button
						class="topbar__icon-btn"
						type="button"
						aria-disabled="true"
						title="Notifications — coming soon"
						disabled
					>
						<span aria-hidden="true">{@html bellIcon}</span>
					</button>
				{/if}
			{/snippet}
			{#snippet account()}
				{#if variant === 'contractor'}
					<a class="topbar__menu-item" href={resolve('/settings/security')}>Password and security</a
					>
				{/if}
				<button
					class="topbar__menu-item"
					type="button"
					onclick={() => void signOut()}
					disabled={isSigningOut}
				>
					<span aria-hidden="true">{@html logoutIcon}</span>
					{isSigningOut ? 'Signing out…' : 'Sign out'}
				</button>
				{#if signOutError}<span class="app-shell__sign-out-error" role="alert">{signOutError}</span
					>{/if}
			{/snippet}
		</Topbar>
		<div class="app-shell__main">{@render children()}</div>
	</div>
	<MobileNav bind:open={mobileOpen} {groups} {brand} {eyebrow} />
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// Where the content column starts and ends, so anything pinned over the page — the action bar at the
	// bottom of a form or detail page — can line up with the page underneath it. `--shell-nav-width` is set
	// on the element itself, because only this component knows whether the sidebar is collapsed.
	.app-shell {
		--shell-edge: var(--space-large);
		--shell-content-left: calc(
			var(--shell-edge) + var(--shell-nav-width, 256px) + var(--space-large)
		);
		--shell-content-right: calc(var(--shell-edge) + var(--space-large));

		position: relative;
		display: flex;
		min-height: 100vh;
		background: var(--color-surface--background);
		padding: var(--shell-edge);
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
		padding: var(--space-large) var(--space-large) var(--space-large) 0;
	}
	.app-shell__sign-out-error {
		display: block;
		padding: 0 var(--space-small) var(--space-small);
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	// The sidebar is hidden here, so the content column runs the full width inside the shell padding.
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
