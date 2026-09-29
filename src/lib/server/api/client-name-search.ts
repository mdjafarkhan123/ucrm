import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';

// The matching clients' ids travel inside the list query's URL, and a URL of about a thousand ids is
// refused outright (measured 2026-09-29: 400 ids pass, 1,000 fail). 200 keeps well clear of that on any
// proxy in front of the database.
export const CLIENT_NAME_SEARCH_LIMIT = 200;

/**
 * A request, quote, or job has no name of its own that says whose it is, so a list searched by a client's
 * name looks the clients up first — through the trigram name index, a few milliseconds at 50,000
 * clients — and the caller folds the returned `client_id.in.(...)` branch into its own or= filter. Doing
 * it as one joined query instead measured 300–860 ms at that size, because no index can serve an OR that
 * spans two tables.
 *
 * `narrowed` is true when more clients match than fit: the list still shows only true matches, but some
 * clients' work is left out, so the page asks the person to type more of the name.
 */
export async function clientNameSearchBranch(
	supabase: SupabaseClient<Database>,
	organizationId: string,
	quotedTerm: string
): Promise<{ ok: true; branch: string; narrowed: boolean } | { ok: false }> {
	const { data, error } = await supabase
		.from('clients')
		.select('id')
		.eq('organization_id', organizationId)
		.is('deleted_at', null)
		.or(`display_name.ilike.${quotedTerm},company_name.ilike.${quotedTerm}`)
		.limit(CLIENT_NAME_SEARCH_LIMIT + 1);
	if (error) return { ok: false };

	const ids = (data ?? []).slice(0, CLIENT_NAME_SEARCH_LIMIT).map((row) => row.id);
	return {
		ok: true,
		branch: ids.length > 0 ? `,client_id.in.(${ids.join(',')})` : '',
		narrowed: (data ?? []).length > CLIENT_NAME_SEARCH_LIMIT
	};
}
