import type { QueryClient } from '@tanstack/svelte-query';
import {
	jafarOrganizationProtectedDocumentsKey,
	jafarOrganizationPreviewKey,
	jafarOrganizationLaunchApprovalKey,
	jafarOrganizationLaunchChecksKey,
	jafarOrganizationProviderWaitsKey,
	jafarOrganizationSetupKey
} from '$lib/jafar/query-keys';
import type { ClientSetupView } from '$lib/setup/client-page';
import type { ProviderWait, ProviderWaitKey } from '$lib/setup/provider-waits';
import type { PreviewCard, PreviewScreenshotUrls, PreviewVersion } from '$lib/setup/preview';
import type { LaunchApprovalRequest } from '$lib/setup/launch-approval';
import type { OwnerLaunchChecklist } from '$lib/setup/launch-checks';

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
	void queryClient.prefetchQuery(organizationProviderWaitsQuery(organizationId));
	void queryClient.prefetchQuery(organizationPreviewQuery(organizationId));
	void queryClient.prefetchQuery(organizationLaunchApprovalQuery(organizationId));
	void queryClient.prefetchQuery(organizationLaunchChecksQuery(organizationId));
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

/** C5: where Jafar fills a client's CRM settings from their accepted answers again (POST). */
export const organizationSetupSettingsCopyUrl = (organizationId: string) =>
	`/api/jafar/organizations/${encodeURIComponent(organizationId)}/setup/settings-copy`;

/** E2: where Jafar reads (GET) and changes (POST) a client's outside waits. */
export const organizationProviderWaitsUrl = (organizationId: string) =>
	`/api/jafar/organizations/${encodeURIComponent(organizationId)}/setup/provider-waits`;

export const organizationProviderWaitsQuery = (organizationId: string) => ({
	queryKey: jafarOrganizationProviderWaitsKey(organizationId),
	queryFn: async (): Promise<{ offered: ProviderWaitKey[]; waits: ProviderWait[] }> => {
		const response = await fetch(organizationProviderWaitsUrl(organizationId));
		const result = (await response.json().catch(() => ({}))) as {
			offered?: ProviderWaitKey[];
			waits?: ProviderWait[];
			error?: string;
		};
		if (!response.ok || !result.offered || !result.waits)
			throw new Error(result.error ?? 'The outside waits could not be loaded.');
		return { offered: result.offered, waits: result.waits };
	},
	staleTime: 30_000
});

/** E3: where Jafar reads (GET), saves (POST) and discards (DELETE) a client's preview draft. */
export const organizationPreviewUrl = (organizationId: string) =>
	`/api/jafar/organizations/${encodeURIComponent(organizationId)}/setup/preview`;

export type OwnerPreviewData = {
	ready: boolean;
	service_keys: string[];
	draft: { version: number; cards: PreviewCard[]; updated_at: string } | null;
	released: PreviewVersion[];
};

export const organizationPreviewQuery = (organizationId: string) => ({
	queryKey: jafarOrganizationPreviewKey(organizationId),
	queryFn: async (): Promise<OwnerPreviewData> => {
		const response = await fetch(organizationPreviewUrl(organizationId));
		const result = (await response.json().catch(() => ({}))) as Partial<OwnerPreviewData> & {
			error?: string;
		};
		if (!response.ok || !result.released)
			throw new Error(result.error ?? 'The preview could not be loaded.');
		return result as OwnerPreviewData;
	},
	staleTime: 30_000
});

/** Where Jafar's screenshots for this client upload to and are shown from. */
export const organizationPreviewScreenshotUrls = (
	organizationId: string
): PreviewScreenshotUrls => {
	const base = `${organizationPreviewUrl(organizationId)}/screenshots`;
	return {
		presign: base,
		view: (key, size) =>
			`${base}?key=${encodeURIComponent(key)}${size === 'thumb' ? '&size=thumb' : ''}`
	};
};

/** E4: where Jafar asks for launch approval (POST), and reads every request (GET); `/resend` and `/record` below. */
export const organizationLaunchApprovalUrl = (organizationId: string) =>
	`/api/jafar/organizations/${encodeURIComponent(organizationId)}/setup/launch-approval`;

export const organizationLaunchApprovalQuery = (organizationId: string) => ({
	queryKey: jafarOrganizationLaunchApprovalKey(organizationId),
	queryFn: async (): Promise<LaunchApprovalRequest[]> => {
		const response = await fetch(organizationLaunchApprovalUrl(organizationId));
		const result = (await response.json().catch(() => ({}))) as {
			requests?: LaunchApprovalRequest[];
			error?: string;
		};
		if (!response.ok || !result.requests)
			throw new Error(result.error ?? 'The launch approvals could not be loaded.');
		return result.requests;
	},
	staleTime: 30_000
});

/** E5: where Jafar reads (GET) and ticks (POST) the newest released preview's launch checklist. */
export const organizationLaunchChecksUrl = (organizationId: string) =>
	`/api/jafar/organizations/${encodeURIComponent(organizationId)}/setup/launch-checks`;

export const organizationLaunchChecksQuery = (organizationId: string) => ({
	queryKey: jafarOrganizationLaunchChecksKey(organizationId),
	queryFn: async (): Promise<OwnerLaunchChecklist | null> => {
		const response = await fetch(organizationLaunchChecksUrl(organizationId));
		const result = (await response.json().catch(() => ({}))) as {
			checklist?: OwnerLaunchChecklist | null;
			error?: string;
		};
		if (!response.ok || result.checklist === undefined)
			throw new Error(result.error ?? 'The launch checks could not be loaded.');
		return result.checklist;
	},
	staleTime: 30_000
});
