import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireClientPermission } from '$lib/server/access/clients';
import { databaseError } from '$lib/server/api/errors';
import { findExactDuplicates, findSimilarClients } from '$lib/server/clients/duplicates';

/**
 * Candidates for the client currently being typed in. Exact email or phone matches block the save;
 * similar names and addresses only warn. Everything is scoped to the caller's own organization.
 */
export const GET: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.view');
	if ('response' in access) return access.response;

	const organizationId = access.auth.organization.id;
	const params = event.url.searchParams;
	const excludeClientId = params.get('exclude_id');

	const [exact, similar] = await Promise.all([
		findExactDuplicates(event.locals.supabase, organizationId, {
			email: params.get('email'),
			phone: params.get('phone'),
			excludeClientId
		}),
		findSimilarClients(event.locals.supabase, organizationId, {
			name: params.get('name'),
			address: params.get('address'),
			excludeClientId
		})
	]);
	if ('failed' in exact || 'failed' in similar) return databaseError();

	const blockedIds = new Set(exact.matches.map((match) => match.id));

	return json({
		exact: exact.matches,
		similar: similar.matches.filter((match) => !blockedIds.has(match.id))
	});
};
