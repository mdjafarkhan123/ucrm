import { QueryClient } from '@tanstack/query-core';

export function createQueryClient() {
	return new QueryClient({
		defaultOptions: {
			queries: { staleTime: 30_000, refetchOnWindowFocus: false }
		}
	});
}
