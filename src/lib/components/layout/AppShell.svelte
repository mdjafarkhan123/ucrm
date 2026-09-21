<script lang="ts">
	import Sidebar, { type NavGroup } from './Sidebar.svelte';
	import Topbar from './Topbar.svelte';
	import MobileNav from './MobileNav.svelte';
	import GlobalSearchDialog from '$lib/components/search/GlobalSearchDialog.svelte';
	import NotificationBell from '$lib/components/jafar/NotificationBell.svelte';
	import TeamNotificationBell from '$lib/components/team/TeamNotificationBell.svelte';
	import { goto } from '$app/navigation';
	import { invalidateAll } from '$app/navigation';
	import { resolve } from '$app/paths';

	import logoutIcon from '@tabler/icons/outline/logout.svg?raw';

	let {
		children,
		variant = 'contractor',
		organizationName,
		logoUrl = null,
		account = null,
		userId,
		pipelineVisible = true,
		clientsVisible = true,
		quotesVisible = true,
		invoicesVisible = true,
		marketingVisible = false,
		filesVisible = true
	}: {
		children: import('svelte').Snippet;
		variant?: 'contractor' | 'owner';
		organizationName?: string | null;
		logoUrl?: string | null;
		account?: { name: string | null; email: string | null; role: string } | null;
		userId?: string;
		pipelineVisible?: boolean;
		clientsVisible?: boolean;
		quotesVisible?: boolean;
		invoicesVisible?: boolean;
		marketingVisible?: boolean;
		filesVisible?: boolean;
	} = $props();
	let mobileOpen = $state(false);
	let sidebarCollapsed = $state(false);
	let signOutError = $state('');
	let searchOpen = $state(false);

	function handleGlobalShortcut(event: KeyboardEvent) {
		if (variant !== 'contractor' || !userId || event.altKey || event.shiftKey) return;
		if (!(event.metaKey || event.ctrlKey) || event.key.toLowerCase() !== 'k') return;

		event.preventDefault();
		searchOpen = true;
	}

	const contractorGroups: NavGroup[] = $derived.by(() => [
		{
			label: 'Overview',
			items: [
				{ label: 'Dashboard', href: '/dashboard', icon: 'dashboard' },
				{ label: 'Schedule', href: '/schedule', icon: 'calendar' }
			]
		},
		{
			label: 'Customers',
			items: [
				{ label: 'Inbox', href: '/communications', icon: 'inbox' },
				...(clientsVisible ? [{ label: 'Clients', href: '/clients', icon: 'users' }] : []),
				{ label: 'Requests', href: '/requests', icon: 'route' },
				...(pipelineVisible ? [{ label: 'Pipeline', href: '/pipeline', icon: 'chartBar' }] : [])
			]
		},
		{
			label: 'Work & Money',
			items: [
				{ label: 'Jobs', href: '/jobs', icon: 'tools' },
				...(quotesVisible ? [{ label: 'Quotes', href: '/quotes', icon: 'fileInvoice' }] : []),
				...(invoicesVisible ? [{ label: 'Invoices', href: '/invoices', icon: 'receipt' }] : []),
				...(filesVisible ? [{ label: 'Files', href: '/files', icon: 'files' }] : [])
			]
		},
		{
			label: 'Growth',
			items: [
				...(marketingVisible
					? [{ label: 'Marketing', href: '/marketing', icon: 'speakerphone' }]
					: []),
				{ label: 'Reputation', href: '/reputation', icon: 'star', unavailable: true },
				{ label: 'Growth Feed', href: '/growth', icon: 'trendingUp', unavailable: true }
			]
		},
		{
			label: 'System',
			items: [
				{ label: 'Settings', href: '/settings', icon: 'settings' },
				{ label: 'Team', href: '/team', icon: 'usersGroup', unavailable: true },
				{ label: 'Notifications', href: '/notifications', icon: 'mail', unavailable: true },
				{ label: 'Usage', href: '/usage', icon: 'chartBar', unavailable: true }
			]
		}
	]);
	const ownerGroups: NavGroup[] = [
		{
			items: [
				{ label: 'Overview', href: '/jafar', icon: 'dashboard' },
				{ label: 'Prospects', href: '/jafar/prospects', icon: 'users' },
				{ label: 'Packages', href: '/jafar/packages', icon: 'package' },
				{ label: 'Organizations', href: '/jafar/organizations', icon: 'building' },
				{ label: 'Operations', href: '/jafar/operations', icon: 'alertTriangle' },
				{ label: 'System emails', href: '/jafar/message-templates', icon: 'mail' },
				{ label: 'Email templates', href: '/jafar/email-templates', icon: 'fileText' },
				{ label: 'Email safety', href: '/jafar/communications', icon: 'shieldCheck' },
				{ label: 'Settings', href: '/jafar/settings', icon: 'settings' }
			]
		}
	];
	const groups = $derived(variant === 'owner' ? ownerGroups : contractorGroups);
	// The sidebar identifies the signed-in business by its own saved name and logo once one exists, rather
	// than the product's generic mark — but never for the owner's Control Room, which is never a business.
	const brand = $derived(
		variant === 'owner' ? 'Control Room' : (organizationName ?? 'Contractor CRM')
	);
	const eyebrow = $derived(variant === 'owner' ? 'Platform owner' : 'Workspace');
	const sidebarLogoUrl = $derived(variant === 'contractor' ? logoUrl : null);
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

<svelte:window onkeydown={handleGlobalShortcut} />

<!-- eslint-disable svelte/no-at-html-tags -->
<div
	class={`app-shell app-shell--${variant}`}
	style={`--shell-nav-width: ${sidebarCollapsed ? '76px' : '256px'}`}
>
	<Sidebar {groups} {brand} {eyebrow} logoUrl={sidebarLogoUrl} bind:collapsed={sidebarCollapsed} />
	<div class="app-shell__body">
		<Topbar
			{accountLabel}
			{account}
			showSecurityLink={variant === 'contractor'}
			{isSigningOut}
			{signOutError}
			onSignOut={() => void signOut()}
			onmenutoggle={() => (mobileOpen = true)}
			onSearchOpen={variant === 'contractor' && userId ? () => (searchOpen = true) : undefined}
		>
			{#snippet notifications()}
				{#if variant === 'owner'}
					<NotificationBell />
				{:else if variant === 'contractor' && userId}
					<TeamNotificationBell />
				{/if}
			{/snippet}
		</Topbar>
		<div class="app-shell__main scroll-y-auto">{@render children()}</div>
	</div>
	<MobileNav bind:open={mobileOpen} {groups} {brand} {eyebrow} logoUrl={sidebarLogoUrl} />
	{#if variant === 'contractor' && userId}
		<GlobalSearchDialog open={searchOpen} {userId} onClose={() => (searchOpen = false)} />
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
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
		overflow: hidden;
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
		overflow: hidden;
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
