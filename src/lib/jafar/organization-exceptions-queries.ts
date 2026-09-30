import type { QueryClient } from '@tanstack/svelte-query';
import type { AccessExceptionsResponse } from '$lib/components/jafar/organization/types';
import { jafarOrganizationExceptionsKey } from '$lib/jafar/query-keys';

// The Access tab's features, limits, and exceptions: one read shared by the tab and its hover prefetch.
export const organizationExceptionsQuery = (organizationId: string) => ({
	queryKey: jafarOrganizationExceptionsKey(organizationId),
	queryFn: async (): Promise<AccessExceptionsResponse> => {
		const response = await fetch(`/api/jafar/organizations/${organizationId}/exceptions`);
		const result = (await response.json()) as AccessExceptionsResponse;
		if (!response.ok) throw new Error(result.error ?? 'Features and limits could not be loaded.');
		return result;
	},
	staleTime: 30_000
});

export function prefetchOrganizationExceptions(queryClient: QueryClient, organizationId: string) {
	void queryClient.prefetchQuery(organizationExceptionsQuery(organizationId));
}
