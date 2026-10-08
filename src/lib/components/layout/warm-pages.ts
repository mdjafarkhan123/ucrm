import { preloadCode } from '$app/navigation';
import type { QueryClient } from '@tanstack/svelte-query';

// The longest the warm-up waits for the open page's own reads before going ahead anyway.
const SETTLE_LIMIT_MS = 10_000;

// Every page is its own JavaScript file, so the first visit to one waits for that file to arrive and the
// click feels stuck. Once the browser is idle this fetches the code for the pages someone moves between all
// day, so those clicks paint straight away; every other sidebar link loads on hover or touch. Skipped on data
// saver or 2G (Google quicklink's rule), so nobody on mobile data pays for pages they may never open. Only a
// page's code is fetched, never its data. Call from onMount; returns the cleanup.
//
// The browser counts as idle while it is only waiting on the network, so given a query client the warm-up
// also waits until the open page's own reads have arrived: on a slow phone it would otherwise share the line
// with them and the page itself would paint later.
export function warmPagesWhenIdle(
	paths: string[],
	queryClient?: QueryClient
): (() => void) | undefined {
	if (paths.length === 0 || onConstrainedConnection()) return;

	let cancelIdle: (() => void) | null = null;
	const warmWhenIdle = () => {
		if (cancelIdle) return;
		const warm = () => {
			for (const path of paths) void preloadCode(path);
		};
		if ('requestIdleCallback' in window) {
			const handle = requestIdleCallback(warm, { timeout: 3000 });
			cancelIdle = () => cancelIdleCallback(handle);
		} else {
			const handle = setTimeout(warm, 1000);
			cancelIdle = () => clearTimeout(handle);
		}
	};

	if (!queryClient || queryClient.isFetching() === 0) {
		warmWhenIdle();
		return () => cancelIdle?.();
	}

	const settled = () => {
		if (queryClient.isFetching() > 0) return;
		stopWaiting();
		warmWhenIdle();
	};
	const unsubscribe = queryClient.getQueryCache().subscribe(settled);
	const limit = setTimeout(() => {
		stopWaiting();
		warmWhenIdle();
	}, SETTLE_LIMIT_MS);
	function stopWaiting() {
		unsubscribe();
		clearTimeout(limit);
	}

	return () => {
		stopWaiting();
		cancelIdle?.();
	};
}

function onConstrainedConnection() {
	const connection = (
		navigator as Navigator & { connection?: { saveData?: boolean; effectiveType?: string } }
	).connection;
	return Boolean(connection?.saveData || connection?.effectiveType?.includes('2g'));
}
