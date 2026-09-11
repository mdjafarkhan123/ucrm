import { QueryClient } from '@tanstack/query-core';

// A 4xx answer (no permission, not found, bad request) is the same answer no matter how many more times
// the app asks. Retrying it anyway is pointless, and if the tab loses focus mid-retry, TanStack Query
// pauses and waits for focus to come back before trying again — which can leave the page stuck on its
// loading skeleton indefinitely instead of ever showing an error. Anything else (a dropped connection,
// a 5xx) is worth the normal 3 retries.
function shouldRetry(failureCount: number, error: unknown) {
	const status = (error as { status?: number } | null)?.status;
	if (status !== undefined && status >= 400 && status < 500) return false;
	return failureCount < 3;
}

export function createQueryClient() {
	return new QueryClient({
		defaultOptions: {
			queries: { staleTime: 30_000, refetchOnWindowFocus: false, retry: shouldRetry }
		}
	});
}
