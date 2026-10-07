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
	import { useQueryClient } from '@tanstack/svelte-query';

	import logoutIcon from '@tabler/icons/outline/logout.svg?raw';

	let {
		children,
		notice,
		variant = 'contractor',
		organizationName,
		logoUrl = null,
		account = null,
		userId,
		inboxVisible = true,
		pipelineVisible = true,
		clientsVisible = true,
		quotesVisible = true,
		invoicesVisible = true,
		marketingVisible = false,
		reviewsVisible = false,
		filesVisible = true,
		supportUnread = 0,
		ownerCanOpen = () => true,
		ownerNotificationsVisible = true
	}: {
		children: import('svelte').Snippet;
		/** An account-wide message shown above every page, such as the overdue-payment banner. */
		notice?: import('svelte').Snippet;
		variant?: 'contractor' | 'owner';
		organizationName?: string | null;
		logoUrl?: string | null;
		account?: { name: string | null; email: string | null; role: string } | null;
		userId?: string;
		inboxVisible?: boolean;
		pipelineVisible?: boolean;
		clientsVisible?: boolean;
		quotesVisible?: boolean;
		invoicesVisible?: boolean;
		marketingVisible?: boolean;
		reviewsVisible?: boolean;
		filesVisible?: boolean;
		/** Owner only: support conversations waiting unread for Uplift, shown on the Support item. */
		supportUnread?: number;
		/** Owner variant: whether the signed-in person may open a page; a teammate sees only their areas. */
		ownerCanOpen?: (href: string) => boolean;
		/** Owner variant: the platform alerts bell, which is the owner's alone. */
		ownerNotificationsVisible?: boolean;
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
				...(inboxVisible ? [{ label: 'Inbox', href: '/communications', icon: 'inbox' }] : []),
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
				...(reviewsVisible ? [{ label: 'Reviews', href: '/reviews', icon: 'star' }] : []),
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
	// The Jafar Panel's two entrances: running Uplift's own business (finding, selling to, and looking
	// after clients) and running the platform those clients use. Settings serves both.
	const allOwnerGroups: NavGroup[] = $derived([
		{
			label: 'Business Management',
			items: [
				{ label: 'Overview', href: '/jafar', icon: 'dashboard' },
				{ label: 'Leads', href: '/jafar/leads', icon: 'target' },
				{ label: 'Applications', href: '/jafar/prospects', icon: 'users' },
				{ label: 'Onboarding', href: '/jafar/onboarding', icon: 'rocket' },
				{ label: 'Client setup', href: '/jafar/setup', icon: 'listCheck' },
				{ label: 'Support', href: '/jafar/support', icon: 'messages', count: supportUnread }
			]
		},
		{
			label: 'Platform Operations',
			items: [
				{ label: 'Organizations', href: '/jafar/organizations', icon: 'building' },
				{ label: 'Packages', href: '/jafar/packages', icon: 'package' },
				{ label: 'Operations', href: '/jafar/operations', icon: 'alertTriangle' }
			]
		},
		{
			// System emails, Email templates and Email safety are set up from Settings (Jafar, 2026-10-07).
			items: [
				{
					label: 'Settings',
					href: '/jafar/settings',
					icon: 'settings',
					matches: ['/jafar/message-templates', '/jafar/email-templates', '/jafar/communications']
				}
			]
		}
	]);
	// A teammate sees only the pages their access opens, and a section with none left disappears.
	const ownerGroups = $derived(
		allOwnerGroups
			.map((group) => ({ ...group, items: group.items.filter((item) => ownerCanOpen(item.href)) }))
			.filter((group) => group.items.length > 0)
	);
	const groups = $derived(variant === 'owner' ? ownerGroups : contractorGroups);
	// The sidebar identifies the signed-in business by its own saved name and logo once one exists, rather
	// than the product's generic mark — but never for the owner's Control Room, which is never a business.
	const brand = $derived(
		variant === 'owner' ? 'Control Room' : (organizationName ?? 'Contractor CRM')
	);
	// The owner's own view passes no `account`; a teammate's carries their name and role.
	const eyebrow = $derived(
		variant === 'owner' ? (account ? 'Uplift team' : 'Platform owner') : 'Workspace'
	);
	const sidebarLogoUrl = $derived(variant === 'contractor' ? logoUrl : null);
	const accountLabel = $derived(
		variant === 'owner' ? (account ? 'Uplift team' : 'Platform owner') : 'Your account'
	);
	let isSigningOut = $state(false);
	const queryClient = useQueryClient();

	async function signOut() {
		isSigningOut = true;
		signOutError = '';
		try {
			const response = await fetch(
				variant === 'owner' ? '/api/jafar/session' : '/api/auth/session',
				{ method: 'DELETE' }
			);
			if (!response.ok) throw new Error('Sign out request failed.');

			// A next sign-in on this same tab must never see this session's cached data.
			queryClient.clear();

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
				{#if variant === 'owner' && ownerNotificationsVisible}
					<NotificationBell />
				{:else if variant === 'contractor' && userId}
					<TeamNotificationBell />
				{/if}
			{/snippet}
		</Topbar>
		{@render notice?.()}
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
