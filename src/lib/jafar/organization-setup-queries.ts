import type { QueryClient } from '@tanstack/svelte-query';
import {
	jafarOrganizationProtectedDocumentsKey,
	jafarOrganizationSetupKey
} from '$lib/jafar/query-keys';
import type { ClientSetupView } from '$lib/setup/client-page';

// The Setup tab's reads (client onboarding B9b, C2), shared by the tab and its hover prefetch so both use the same keys.

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

/** C2: the client's setup as sent to Uplift — send `send`, or the newest when null. */
export const organizationSetupQuery = (organizationId: string, send: number | null) => ({
	queryKey: jafarOrganizationSetupKey(organizationId, send),
	queryFn: async (): Promise<ClientSetupView> => {
		const response = await fetch(
			`/api/jafar/organizations/${encodeURIComponent(organizationId)}/setup${send ? `?send=${send}` : ''}`
		);
		const result = (await response.json().catch(() => ({}))) as ClientSetupView & {
			error?: string;
		};
		if (!response.ok) throw new Error(result.error ?? 'The client’s setup could not be loaded.');
		return result;
	},
	// Photo previews are signed links that last about an hour.
	staleTime: 30_000,
	refetchInterval: 30 * 60 * 1000
});

export const organizationSetupRemindersUrl = (organizationId: string) =>
	`/api/jafar/organizations/${encodeURIComponent(organizationId)}/setup/reminders`;

export function prefetchOrganizationSetup(queryClient: QueryClient, organizationId: string) {
	void queryClient.prefetchQuery(organizationSetupQuery(organizationId, null));
	void queryClient.prefetchQuery(organizationProtectedDocumentsQuery(organizationId));
}

/** C3: where Jafar's Accept and Send back on one section go (POST). */
export const organizationSetupReviewsUrl = (organizationId: string) =>
	`/api/jafar/organizations/${encodeURIComponent(organizationId)}/setup/reviews`;

/** C3c: where Jafar records Uplift's answer to a help request (POST). */
export const organizationSetupHelpAnswersUrl = (organizationId: string) =>
	`/api/jafar/organizations/${encodeURIComponent(organizationId)}/setup/help-answers`;

/** C4: where Jafar records Ready for Uplift (POST) or takes it back with a reason (DELETE). */
export const organizationSetupReadyUrl = (organizationId: string) =>
	`/api/jafar/organizations/${encodeURIComponent(organizationId)}/setup/ready`;
