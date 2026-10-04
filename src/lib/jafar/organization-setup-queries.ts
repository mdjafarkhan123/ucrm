import type { QueryClient } from '@tanstack/svelte-query';
import { jafarOrganizationProtectedDocumentsKey } from '$lib/jafar/query-keys';

// Client onboarding B9b: the Setup tab's one read, shared by the tab and its hover prefetch so both use the same key.

/** One protected document as Jafar's list shows it. Mirrors `$lib/server/setup/protected-documents`. */
export type ProtectedDocumentListing = {
	id: string;
	question: string;
	name: string;
	size_bytes: number;
	state: 'uploading' | 'checking' | 'ready' | 'refused' | 'deleted';
	problem: string | null;
	uploaded_at: string | null;
	delete_after: string | null;
	deleted_at: string | null;
	in_answer: boolean;
};

/** Where Jafar's actions on one document go: open (GET), delete (DELETE), provider step finished (PATCH). */
export const protectedDocumentUrl = (organizationId: string, documentId: string) =>
	`/api/jafar/organizations/${encodeURIComponent(organizationId)}/setup/protected-documents/${encodeURIComponent(documentId)}`;

export const organizationProtectedDocumentsQuery = (organizationId: string) => ({
	queryKey: jafarOrganizationProtectedDocumentsKey(organizationId),
	queryFn: async (): Promise<ProtectedDocumentListing[]> => {
		const response = await fetch(
			`/api/jafar/organizations/${encodeURIComponent(organizationId)}/setup/protected-documents`
		);
		const result = (await response.json().catch(() => ({}))) as {
			documents?: ProtectedDocumentListing[];
			error?: string;
		};
		if (!response.ok || !result.documents)
			throw new Error(result.error ?? 'Protected documents could not be loaded.');
		return result.documents;
	},
	staleTime: 30_000
});

export function prefetchOrganizationSetup(queryClient: QueryClient, organizationId: string) {
	void queryClient.prefetchQuery(organizationProtectedDocumentsQuery(organizationId));
}
