import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { permissionIsEnabled, resolveOrganizationAccess } from '$lib/server/access/effective';
import { hasPermission } from '$lib/server/access/permission';
import {
	PRIVATE_READ_HEADERS,
	databaseError,
	unauthorized,
	validationError
} from '$lib/server/api/errors';
import { searchCoreRecords } from '$lib/server/search/core-records';
import { searchConversations } from '$lib/server/search/conversations';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { globalSearchQuerySchema } from '$lib/server/validation/search.schema';

export const GET: RequestHandler = async (event) => {
	const parsed = globalSearchQuerySchema.safeParse({ q: event.url.searchParams.get('q') ?? '' });
	if (!parsed.success) {
		return validationError({ q: parsed.error.issues[0]?.message ?? 'Enter a search term.' });
	}

	const auth = await getOrganizationContext(event);
	if (!auth) return unauthorized();

	try {
		const access = await resolveOrganizationAccess(
			event.locals.supabase,
			auth.organization.id,
			auth.user.id
		);
		// Conversation results open the shared inbox, so they go when the plan has no inbox.
		const inboxIncluded = access.features['communications.inbox'] === true;
		const canViewTeamConversations =
			inboxIncluded && hasPermission(access, 'conversations.view_team');
		const canViewAssignedConversations =
			inboxIncluded && hasPermission(access, 'conversations.view_assigned');
		const [coreGroups, conversations] = await Promise.all([
			searchCoreRecords(event.locals.supabase, auth.organization.id, parsed.data.q, {
				clients: hasPermission(access, 'customers.view'),
				requests: permissionIsEnabled('requests.view', access.features),
				quotes: hasPermission(access, 'quotes.view'),
				jobs: hasPermission(access, 'jobs.view'),
				invoices: hasPermission(access, 'invoices.view')
			}),
			canViewTeamConversations || canViewAssignedConversations
				? searchConversations(getOwnerSupabaseClient(), auth.organization.id, parsed.data.q, {
						canViewTeam: canViewTeamConversations,
						canViewAssigned: canViewAssignedConversations,
						userId: auth.user.id
					})
				: Promise.resolve(null)
		]);
		const groups = conversations === null ? coreGroups : { ...coreGroups, conversations };

		return json({ query: parsed.data.q, groups }, { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Global search failed.', error);
		return databaseError();
	}
};
