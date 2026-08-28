// Snippets: short, folder-organized reusable text for the Conversations composer (Communications Part 6,
// first slice). See docs/contractor-email-contract.md § Templates, snippets, and branding.

export type CommunicationSnippet = {
	id: string;
	folder: string | null;
	title: string;
	body: string;
	created_at: string;
	updated_at: string;
};

export type CommunicationSnippetPage = {
	items: CommunicationSnippet[];
	next_cursor: string | null;
};

export type SnippetSearch = { folder?: string; search?: string };

export type SnippetDraft = { folder: string | null; title: string; body: string };

export class SnippetWriteError extends Error {
	constructor(
		message: string,
		public readonly fieldErrors: Record<string, string> = {}
	) {
		super(message);
		this.name = 'SnippetWriteError';
	}
}

export const communicationSnippetsKey = (query: SnippetSearch = {}) =>
	['communications', 'snippets', query.folder ?? 'all', query.search ?? ''] as const;

export async function fetchCommunicationSnippets(
	query: SnippetSearch = {},
	cursor?: string
): Promise<CommunicationSnippetPage> {
	const params = new URLSearchParams();
	if (query.folder) params.set('folder', query.folder);
	if (query.search) params.set('search', query.search);
	if (cursor) params.set('cursor', cursor);
	const response = await fetch(`/api/communications/snippets?${params.toString()}`);
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw new Error(result.error ?? 'Snippets could not be loaded.');
	return result as CommunicationSnippetPage;
}

async function saveSnippet(url: string, method: 'POST' | 'PATCH', body: object) {
	const response = await fetch(url, {
		method,
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new SnippetWriteError(
			result.error ?? 'That snippet could not be saved.',
			result.field_errors ?? {}
		);
	}
	return (result as { item: CommunicationSnippet }).item;
}

export function createCommunicationSnippet(draft: SnippetDraft) {
	return saveSnippet('/api/communications/snippets', 'POST', draft);
}

export function updateCommunicationSnippet(id: string, draft: Partial<SnippetDraft>) {
	return saveSnippet(`/api/communications/snippets/${id}`, 'PATCH', draft);
}

export async function deleteCommunicationSnippet(id: string): Promise<void> {
	const response = await fetch(`/api/communications/snippets/${id}`, { method: 'DELETE' });
	if (!response.ok) {
		const result = await response.json().catch(() => ({}));
		throw new SnippetWriteError(result.error ?? 'That snippet could not be deleted.');
	}
}
