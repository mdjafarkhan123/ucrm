<script lang="ts">
	import { navigating } from '$app/state';
	import { useQueryClient } from '@tanstack/svelte-query';
	import AppShell from '$lib/components/layout/AppShell.svelte';
	import RouteSkeleton from '$lib/components/layout/RouteSkeleton.svelte';
	import { notificationsKey } from '$lib/jafar/notifications';
	import {
		jafarEmailHealthKey,
		jafarEmailTemplatesKey,
		jafarMessageTemplatesKey,
		jafarOperationsKey,
		jafarOrganizationKey,
		jafarOrganizationsKey,
		jafarPackageKey,
		jafarPackagesKey,
		jafarProspectsKey,
		jafarSettingsKey
	} from '$lib/jafar/query-keys';
	import { jafarSupportInboxKey } from '$lib/support/api';
	let { children } = $props();
	const queryClient = useQueryClient();

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

<AppShell variant="owner">
	{#if showLoadingSkeleton}
		<RouteSkeleton />
	{:else}
		{@render children()}
	{/if}
</AppShell>
