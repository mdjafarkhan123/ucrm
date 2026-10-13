<script lang="ts">
	import type { NavGroup, NavItem } from './navigation';
	import type { ShellFrame } from './presentations/types';
	import Topbar from './Topbar.svelte';
	import GlobalSearchDialog from '$lib/components/search/GlobalSearchDialog.svelte';
	import ProfilePhotoDialog from '$lib/components/profile/ProfilePhotoDialog.svelte';
	import { leaveThisComputer } from '$lib/team/browser-alerts';
	import NotificationBell from '$lib/components/jafar/NotificationBell.svelte';
	import TeamNotificationBell from '$lib/components/team/TeamNotificationBell.svelte';
	import HeaderTimer from '$lib/components/time-clock/HeaderTimer.svelte';
	import { goto } from '$app/navigation';
	import { invalidateAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { useQueryClient } from '@tanstack/svelte-query';
	import { fallbackContractorNavigation, type ContractorNavigation } from '$lib/account/navigation';

	let {
		Frame,
		children,
		notice,
		variant = 'contractor',
		organizationName,
		logoUrl = null,
		account = null,
		userId,
		navigation = fallbackContractorNavigation,
		supportUnread = 0,
		ownerCanOpen = () => true,
		ownerPhoto = null
	}: {
		Frame: ShellFrame;
		children: import('svelte').Snippet;
		/** An account-wide message shown above every page, such as the overdue-payment banner. */
		notice?: import('svelte').Snippet;
		variant?: 'contractor' | 'owner';
		organizationName?: string | null;
		logoUrl?: string | null;
		account?: {
			name: string | null;
			email: string | null;
			role: string;
			avatarUrl?: string | null;
		} | null;
		userId?: string;
		/** Contractor variant: the menu items this member may open, from their package and permissions. */
		navigation?: ContractorNavigation;
		/** Owner only: support conversations waiting unread for Uplift, shown on the Support item. */
		supportUnread?: number;
		/** Owner variant: whether the signed-in person may open a page; a teammate sees only their areas. */
		ownerCanOpen?: (href: string) => boolean;
		/** Owner variant: the signed-in person's own photo — Jafar's, or a teammate's. */
		ownerPhoto?: { id: string; url: string | null; name: string | null } | null;
	} = $props();
	let mobileOpen = $state(false);
	let sidebarCollapsed = $state(false);
	let signOutError = $state('');
	let searchOpen = $state(false);
	let photoOpen = $state(false);
	// The signed-in person's own photo, in the top bar and its menu. A contractor's lives on their profile;
	// Jafar and his teammates are separate logins (ADR 0008), so theirs has its own address.
	const photo = $derived.by(() => {
		if (variant === 'owner') {
			return ownerPhoto ? { ...ownerPhoto, endpoint: '/api/jafar/account/photo' } : null;
		}
		if (!userId || !account) return null;
		return {
			id: userId,
			url: account.avatarUrl ?? null,
			name: account.name ?? account.email,
			endpoint: '/api/profile/photo'
		};
	});

	// Toasts open just below the header, never over its controls (see ToastViewport). The header's height
	// changes with the presentation, the screen width and a running timer's phone row, so it is measured.
	$effect(() => {
		const header = document.querySelector<HTMLElement>('[data-shell-header]');
		if (!header) return;
		const root = document.documentElement;
		const publish = () =>
			root.style.setProperty(
				'--toast-top',
				`${Math.round(header.getBoundingClientRect().bottom) + 8}px`
			);
		publish();
		const observer = new ResizeObserver(publish);
		observer.observe(header);
		return () => {
			observer.disconnect();
			root.style.removeProperty('--toast-top');
		};
	});

	function handleGlobalShortcut(event: KeyboardEvent) {
		if (variant !== 'contractor' || !userId || event.altKey || event.shiftKey) return;
		if (!(event.metaKey || event.ctrlKey) || event.key.toLowerCase() !== 'k') return;

		event.preventDefault();
		searchOpen = true;
	}

	type ContractorNavItem = NavItem & { area?: keyof ContractorNavigation };
	const allContractorGroups: Array<{ label: string; items: ContractorNavItem[] }> = [
		{
			label: 'Overview',
			items: [
				{ label: 'Dashboard', href: '/dashboard', icon: 'dashboard' },
				{ label: 'Schedule', href: '/schedule', icon: 'calendar', area: 'schedule' },
				{ label: 'Timesheets', href: '/timesheets', icon: 'clock', area: 'timesheets' }
			]
		},
		{
			label: 'Customers',
			items: [
				{ label: 'Inbox', href: '/communications', icon: 'inbox', area: 'inbox' },
				{ label: 'Clients', href: '/clients', icon: 'users', area: 'clients' },
				{ label: 'Requests', href: '/requests', icon: 'route', area: 'requests' },
				{ label: 'Pipeline', href: '/pipeline', icon: 'chartBar', area: 'pipeline' }
			]
		},
		{
			label: 'Work & Money',
			items: [
				{ label: 'Jobs', href: '/jobs', icon: 'tools', area: 'jobs' },
				{ label: 'Quotes', href: '/quotes', icon: 'fileInvoice', area: 'quotes' },
				{ label: 'Invoices', href: '/invoices', icon: 'receipt', area: 'invoices' },
				{ label: 'Files', href: '/files', icon: 'files', area: 'files' }
			]
		},
		{
			label: 'Growth',
			items: [
				{ label: 'Marketing', href: '/marketing', icon: 'speakerphone', area: 'marketing' },
				{ label: 'Reviews', href: '/reviews', icon: 'star', area: 'reviews' },
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
	];
	// An item shows only when its area is open to this member, and a section with none left disappears.
	const contractorGroups: NavGroup[] = $derived(
		allContractorGroups
			.map((group) => ({
				label: group.label,
				items: group.items.filter((item) => !item.area || navigation[item.area])
			}))
			.filter((group) => group.items.length > 0)
	);
	// The Jafar Panel's two entrances: running Uplift's own business (finding, selling to, and looking
	// after clients) and running the platform those clients use. Settings serves both.
	const allOwnerGroups: NavGroup[] = $derived([
		{
			label: 'Business Management',
			items: [
				{ label: 'Overview', href: '/jafar', icon: 'dashboard' },
				{ label: 'Leads', href: '/jafar/leads', icon: 'target' },
				{ label: 'Deals', href: '/jafar/deals', icon: 'trendingUp' },
				{ label: 'Calendar', href: '/jafar/calendar', icon: 'calendar' },
				{ label: 'Activity report', href: '/jafar/leads/report', icon: 'chartBar' },
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
	// A teammate sees only the pages their access opens, and a section with none left disappears. Settings stay
	// Jafar's, so a teammate's last item is their own My preferences instead (D3b).
	const ownerGroups = $derived(
		allOwnerGroups
			.map((group) => ({
				...group,
				items: group.items
					.map((item) =>
						item.href === '/jafar/settings' && !ownerCanOpen(item.href)
							? { label: 'My preferences', href: '/jafar/settings/preferences', icon: item.icon }
							: item
					)
					.filter((item) => ownerCanOpen(item.href))
			}))
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
			// The next person on a shared computer must never see this person's browser alerts. This needs the
			// session, so it goes first. It never blocks signing out.
			if (variant === 'contractor') await leaveThisComputer();
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

<Frame
	{groups}
	{brand}
	{eyebrow}
	logoUrl={sidebarLogoUrl}
	{variant}
	{notice}
	bind:mobileOpen
	bind:sidebarCollapsed
>
	{#snippet header(
		Header: import('./presentations/header-types').HeaderFrame,
		identity?: import('svelte').Snippet
	)}
		<Topbar
			{Header}
			{identity}
			searchPlaceholder={variant === 'owner' ? 'Search' : 'Search anything in your workspace'}
			{accountLabel}
			{account}
			avatar={photo}
			onEditPhoto={photo ? () => (photoOpen = true) : undefined}
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
			{#snippet timer()}
				{#if variant === 'contractor' && userId}<HeaderTimer />{/if}
			{/snippet}
		</Topbar>
	{/snippet}
	{@render children()}
	{#if variant === 'contractor' && userId}
		<GlobalSearchDialog open={searchOpen} {userId} onClose={() => (searchOpen = false)} />
	{/if}
	{#if photo}
		<ProfilePhotoDialog
			open={photoOpen}
			avatarId={photo.id}
			name={photo.name}
			avatarUrl={photo.url}
			endpoint={photo.endpoint}
			onClose={() => (photoOpen = false)}
		/>
	{/if}
</Frame>
