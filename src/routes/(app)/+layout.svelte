<script lang="ts">
	import { onMount } from 'svelte';
	import { preloadCode } from '$app/navigation';
	import { resolve } from '$app/paths';
	import AppShell from '$lib/components/layout/AppShell.svelte';
	import type { LayoutData } from './$types';

	let { data, children }: { data: LayoutData; children: import('svelte').Snippet } = $props();

	// Every page is its own JavaScript file, so the first visit to one waits for that file to arrive and
	// the click feels stuck. This fetches the files for the pages the office moves between all day once
	// the browser has nothing else to do, so those clicks paint straight away. Hovering a link already
	// does the same thing on its own; this covers the clicks that come too fast for a hover.
	// The id in the client path is a placeholder — only the page's code is fetched, never its data.
	const warmRoutes = [
		resolve('/(app)/dashboard'),
		resolve('/(app)/schedule'),
		resolve('/(app)/clients'),
		resolve('/(app)/clients/new'),
		resolve('/(app)/clients/[id]', { id: 'warm' }),
		resolve('/(app)/requests'),
		resolve('/(app)/requests/new'),
		resolve('/(app)/requests/[id]', { id: 'warm' }),
		resolve('/(app)/quotes'),
		resolve('/(app)/quotes/new'),
		resolve('/(app)/jobs'),
		resolve('/(app)/jobs/new'),
		resolve('/(app)/jobs/[id]', { id: 'warm' }),
		resolve('/(app)/pipeline'),
		resolve('/(app)/pipeline/outcomes'),
		resolve('/(app)/communications'),
		resolve('/(app)/settings'),
		resolve('/(app)/settings/business-profile'),
		resolve('/(app)/settings/branding'),
		resolve('/(app)/settings/business-hours'),
		resolve('/(app)/settings/taxes'),
		resolve('/(app)/settings/price-book'),
		resolve('/(app)/settings/quotes'),
		resolve('/(app)/settings/communications/email'),
		resolve('/(app)/settings/communications/blocked-addresses'),
		resolve('/(app)/settings/communications/website-chat'),
		resolve('/(app)/settings/communications/snippets'),
		resolve('/(app)/settings/communications/templates'),
		resolve('/(app)/settings/team'),
		resolve('/(app)/settings/team/[userId]', { userId: 'warm' })
	];

	onMount(() => {
		const warm = () => {
			for (const path of warmRoutes) void preloadCode(path);
		};

		if ('requestIdleCallback' in window) {
			const handle = requestIdleCallback(warm, { timeout: 3000 });
			return () => cancelIdleCallback(handle);
		}

		const handle = setTimeout(warm, 1000);
		return () => clearTimeout(handle);
	});
</script>

<AppShell organizationName={data.organization?.name} logoUrl={data.logoUrl} account={data.account}
	>{@render children()}</AppShell
>
