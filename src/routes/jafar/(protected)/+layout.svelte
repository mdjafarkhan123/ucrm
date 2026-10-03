<script lang="ts">
	import { navigating } from '$app/state';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import AppShell from '$lib/components/layout/AppShell.svelte';
	import RouteSkeleton from '$lib/components/layout/RouteSkeleton.svelte';
	import { notificationsKey } from '$lib/jafar/notifications';
	import {
		jafarEmailHealthKey,
		jafarEmailTemplatesKey,
		jafarMessageTemplatesKey,
		jafarOnboardingKey,
		jafarOperationsKey,
		jafarOrganizationKey,
		jafarOrganizationsKey,
		jafarPackageKey,
		jafarPackagesKey,
		jafarProspectsKey,
		jafarSetupEditorKey,
		jafarSettingsKey
	} from '$lib/jafar/query-keys';
	import {
		fetchSupportInboxUnread,
		fetchSupportOwnerTopic,
		jafarSupportInboxKey,
		jafarSupportKey,
		jafarSupportUnreadKey
	} from '$lib/support/api';
	import { SUPPORT_FALLBACK_REFRESH_MS, listenForSupportActivity } from '$lib/support/live';
	let { children } = $props();
	const queryClient = useQueryClient();

	// Support conversations waiting unread for Uplift: the number on the Support menu item, on every page.
	const supportUnread = createQuery(() => ({
		queryKey: jafarSupportUnreadKey,
		queryFn: fetchSupportInboxUnread
	}));

	// Support Inbox activity arrives live on this session's own secret channel (D2). Each ping refreshes the
	// count, and the inbox and open conversation when they are on screen, and the onboarding list's unread
	// column. If the channel cannot be issued, the same refresh runs every 30 seconds instead.
	$effect(() => {
		const refresh = () => {
			void queryClient.invalidateQueries({ queryKey: jafarSupportKey });
			void queryClient.invalidateQueries({ queryKey: jafarOnboardingKey });
		};
		let stop: (() => void) | null = null;
		let fallback: ReturnType<typeof setInterval> | null = null;
		let cancelled = false;
		fetchSupportOwnerTopic()
			.then((topic) => {
				if (!cancelled) stop = listenForSupportActivity(topic, refresh);
			})
			.catch(() => {
				if (cancelled) return;
				fallback = setInterval(() => {
					if (document.visibilityState === 'visible') refresh();
				}, SUPPORT_FALLBACK_REFRESH_MS);
			});
		return () => {
			cancelled = true;
			stop?.();
			if (fallback !== null) clearInterval(fallback);
		};
	});

	function hasCachedData(queryKey: readonly unknown[]) {
		return queryClient
			.getQueryCache()
			.findAll({ queryKey })
			.some((query) => query.state.data !== undefined);
	}

	function hasCachedRouteData(pathname: string) {
		if (pathname === '/jafar') {
			return hasCachedData(jafarOrganizationsKey);
		}
		if (pathname.startsWith('/jafar/prospects')) {
			return hasCachedData(jafarProspectsKey);
		}
		if (pathname.startsWith('/jafar/organizations/')) {
			const organizationId = pathname.slice('/jafar/organizations/'.length).split('/')[0];
			return hasCachedData(jafarOrganizationKey(organizationId));
		}
		if (pathname === '/jafar/organizations') {
			return hasCachedData(jafarOrganizationsKey);
		}
		if (pathname === '/jafar/onboarding') {
			return hasCachedData(jafarOnboardingKey);
		}
		if (pathname === '/jafar/setup' || pathname.startsWith('/jafar/setup/')) {
			return hasCachedData(jafarSetupEditorKey);
		}
		if (pathname.startsWith('/jafar/packages/')) {
			return hasCachedData(jafarPackageKey(pathname.slice('/jafar/packages/'.length)));
		}
		if (pathname === '/jafar/packages') {
			return hasCachedData(jafarPackagesKey);
		}
		if (pathname === '/jafar/operations') {
			return hasCachedData(jafarOperationsKey);
		}
		if (pathname === '/jafar/message-templates') {
			return hasCachedData(jafarMessageTemplatesKey);
		}
		if (pathname === '/jafar/email-templates') {
			return hasCachedData(jafarEmailTemplatesKey);
		}
		if (pathname === '/jafar/communications') {
			return hasCachedData(jafarEmailHealthKey);
		}
		if (pathname === '/jafar/settings') {
			return hasCachedData(jafarSettingsKey);
		}
		if (pathname === '/jafar/support') {
			return hasCachedData(jafarSupportInboxKey);
		}
		if (pathname === '/jafar/notifications') {
			return hasCachedData(notificationsKey);
		}
		return false;
	}

	const showLoadingSkeleton = $derived.by(() => {
		const targetPath = navigating.to?.url.pathname;
		return targetPath !== undefined && !hasCachedRouteData(targetPath);
	});
</script>

<AppShell variant="owner" supportUnread={supportUnread.data?.unread ?? 0}>
	{#if showLoadingSkeleton}
		<RouteSkeleton />
	{:else}
		{@render children()}
	{/if}
</AppShell>
