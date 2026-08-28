<script lang="ts">
	import { navigating } from '$app/state';
	import { useQueryClient } from '@tanstack/svelte-query';
	import AppShell from '$lib/components/layout/AppShell.svelte';
	import OwnerRouteSkeleton from '$lib/components/layout/OwnerRouteSkeleton.svelte';
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
			return hasCachedData(['jafar', 'organizations']);
		}
		if (pathname.startsWith('/jafar/prospects')) {
			return hasCachedData(['jafar', 'prospects']);
		}
		if (pathname === '/jafar/packages') {
			return hasCachedData(['jafar', 'packages']);
		}
		if (pathname.startsWith('/jafar/organizations/')) {
			const organizationId = pathname.slice('/jafar/organizations/'.length).split('/')[0];
			return hasCachedData(['jafar', 'organizations', organizationId]);
		}
		if (pathname === '/jafar/organizations') {
			return hasCachedData(['jafar', 'organizations']);
		}
		if (pathname === '/jafar/operations') {
			return hasCachedData(['jafar', 'operations']);
		}
		if (pathname === '/jafar/message-templates') {
			return hasCachedData(['jafar', 'message-templates']);
		}
		if (pathname === '/jafar/email-templates') {
			return hasCachedData(['jafar', 'email-templates']);
		}
		if (pathname === '/jafar/communications') {
			return hasCachedData(['jafar', 'communications', 'email-health']);
		}
		if (pathname === '/jafar/settings') {
			return hasCachedData(['jafar', 'settings']);
		}
		if (pathname === '/jafar/notifications') {
			return hasCachedData(['jafar', 'notifications']);
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
		<OwnerRouteSkeleton />
	{:else}
		{@render children()}
	{/if}
</AppShell>
