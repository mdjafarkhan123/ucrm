import type { QueryClient } from '@tanstack/svelte-query';
import type { BillingResponse } from '$lib/components/jafar/organization/types';
import { jafarOrganizationBillingKey } from '$lib/jafar/query-keys';

// The Billing tab's one read, shared by the tab itself and its hover prefetch so both use the same key.
export const organizationBillingQuery = (organizationId: string) => ({
	queryKey: jafarOrganizationBillingKey(organizationId),
	queryFn: async (): Promise<BillingResponse> => {
		const response = await fetch(`/api/jafar/organizations/${organizationId}/billing`);
		const result = (await response.json()) as BillingResponse;
		if (!response.ok) throw new Error(result.error ?? 'Billing could not be loaded.');
		return result;
	},
	staleTime: 30_000
});

export function prefetchOrganizationBilling(queryClient: QueryClient, organizationId: string) {
	void queryClient.prefetchQuery(organizationBillingQuery(organizationId));
}
