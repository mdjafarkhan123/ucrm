export type GlobalSearchResultType =
	'client' | 'request' | 'quote' | 'job' | 'invoice' | 'conversation';

export type GlobalSearchResult = {
	id: string;
	type: GlobalSearchResultType;
	title: string;
	subtitle: string | null;
	href: string;
};

export type GlobalSearchGroup =
	'clients' | 'requests' | 'quotes' | 'jobs' | 'invoices' | 'conversations';

export type GlobalSearchResponse = {
	query: string;
	groups: Partial<Record<GlobalSearchGroup, GlobalSearchResult[]>>;
};

export const globalSearchKey = (userId: string, query: string) =>
	['global-search', userId, query] as const;

export async function fetchGlobalSearch(query: string): Promise<GlobalSearchResponse> {
	const params = new URLSearchParams({ q: query });
	const response = await fetch(`/api/search?${params.toString()}`);
	if (!response.ok) {
		const body = (await response.json().catch(() => null)) as { error?: string } | null;
		const error = new Error(body?.error ?? 'We could not search right now. Try again.') as Error & {
			status?: number;
		};
		error.status = response.status;
		throw error;
	}
	return response.json() as Promise<GlobalSearchResponse>;
}
