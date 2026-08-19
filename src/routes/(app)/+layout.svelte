<script lang="ts">
	import { onMount } from 'svelte';
	import { preloadCode } from '$app/navigation';
	import { resolve } from '$app/paths';
	import AppShell from '$lib/components/layout/AppShell.svelte';

	let { children } = $props();

	// Every page is its own JavaScript file, so the first visit to one waits for that file to arrive and
	// the click feels stuck. This fetches the files for the pages the office moves between all day once
	// the browser has nothing else to do, so those clicks paint straight away. Hovering a link already
	// does the same thing on its own; this covers the clicks that come too fast for a hover.
	// The id in the client path is a placeholder — only the page's code is fetched, never its data.
	const warmRoutes = [
		resolve('/(app)/dashboard'),
		resolve('/(app)/clients'),
		resolve('/(app)/clients/new'),
		resolve('/(app)/clients/[id]', { id: 'warm' }),
		resolve('/(app)/requests'),
		resolve('/(app)/requests/new'),
		resolve('/(app)/requests/[id]', { id: 'warm' }),
		resolve('/(app)/pipeline'),
		resolve('/(app)/pipeline/outcomes')
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

<AppShell>{@render children()}</AppShell>
