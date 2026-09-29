import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { packageSystemRebuilding } from '$lib/server/packages/rebuilding';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { resolveOrganizationAccess } from '$lib/server/access/effective';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

const eventSelect =
	'id, organization_id, package_version_id, action, starts_at, access_until_date, target_grant_id, reason, actor_kind, actor_owner_email, occurred_at, created_at';

async function getFreeAccessState(
	client: ReturnType<typeof getOwnerSupabaseClient>,
	organizationId: string
) {
	const [
		{ data: organization, error: organizationError },
		{ data: agreement, error: agreementError },
		{ data: events, error: eventsError }
	] = await Promise.all([
		client.from('organizations').select('id, name').eq('id', organizationId).maybeSingle(),
		client
			.from('organization_package_agreements')
			.select('id')
			.eq('organization_id', organizationId)
			.limit(1)
			.maybeSingle(),
		client
			.from('organization_free_access_events')
			.select(eventSelect)
			.eq('organization_id', organizationId)
			.order('occurred_at', { ascending: false })
			.order('id', { ascending: false })
	]);

	if (organizationError) throw organizationError;
	if (agreementError) throw agreementError;
	if (eventsError) throw eventsError;
	if (!organization) return null;

	return {
		organization,
		has_package_assignment: agreement !== null,
		events: events ?? []
	};
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	try {
		const client = getOwnerSupabaseClient();
		const state = await getFreeAccessState(client, parsedId.data);
		if (!state) return json({ error: 'Organization was not found.' }, { status: 404 });
		const access = await resolveOrganizationAccess(client, parsedId.data);
		return json({
			organization: state.organization,
			has_package_assignment: state.has_package_assignment,
			free_access: access.free_access,
			events: state.events
		});
	} catch (error) {
		console.error('Could not load organization free access.', error);
		return json({ error: 'Free access could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = (event) => packageSystemRebuilding(event);
