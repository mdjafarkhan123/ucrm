import type { QueryClient } from '@tanstack/svelte-query';
import type { AccessComparisonResponse, ExperienceTabResponse } from '$lib/experience/types';
import {
	jafarOrganizationAccessComparisonKey,
	jafarOrganizationExperienceKey
} from '$lib/jafar/query-keys';

// The Experience tab's profile, decision history and confirmable definitions: one read shared by the tab
// and its hover prefetch.
export const organizationExperienceQuery = (organizationId: string) => ({
	queryKey: jafarOrganizationExperienceKey(organizationId),
	queryFn: async (): Promise<ExperienceTabResponse> => {
		const response = await fetch(`/api/jafar/organizations/${organizationId}/experience`);
		const result = (await response.json()) as ExperienceTabResponse;
		if (!response.ok)
			throw new Error(result.error ?? 'The experience profile could not be loaded.');
		return result;
	},
	staleTime: 30_000
});

export function prefetchOrganizationExperience(queryClient: QueryClient, organizationId: string) {
	void queryClient.prefetchQuery(organizationExperienceQuery(organizationId));
}

// B5: loaded only when the comparison section is opened, never with the tab itself.
export const organizationAccessComparisonQuery = (organizationId: string) => ({
	queryKey: jafarOrganizationAccessComparisonKey(organizationId),
	queryFn: async (): Promise<AccessComparisonResponse> => {
		const response = await fetch(`/api/jafar/organizations/${organizationId}/access-comparison`);
		const result = (await response.json()) as AccessComparisonResponse;
		if (!response.ok) throw new Error(result.error ?? 'The access comparison could not be loaded.');
		return result;
	},
	staleTime: 30_000
});
