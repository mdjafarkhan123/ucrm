import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

// Read-only: the commercial timezone, paid-through state, and any pending closure. Money is recorded
// through the billing route.
async function getCommercialState(organizationId: string) {
	const client = getOwnerSupabaseClient();
	const [
		{ data: organization, error: organizationError },
		{ data: state, error: stateError },
		{ data: settings, error: settingsError },
		{ data: closure, error: closureError }
	] = await Promise.all([
		client
			.from('organizations')
			.select('id, name, lifecycle_status')
			.eq('id', organizationId)
			.maybeSingle(),
		client
			.from('organization_commercial_state')
			.select(
				'paid_through_date, paid_through_source, grace_ends_at, grace_basis_timezone, last_event_id, state_version, updated_at'
			)
			.eq('organization_id', organizationId)
			.maybeSingle(),
		client
			.from('organization_commercial_settings')
			.select('commercial_timezone, timezone_source')
			.eq('organization_id', organizationId)
			.maybeSingle(),
		client
			.from('organization_closure_records')
			.select('id, reason, started_at, deadline_at')
			.eq('organization_id', organizationId)
			.eq('status', 'pending_closure')
			.maybeSingle()
	]);

	if (organizationError) throw organizationError;
	if (stateError) throw stateError;
	if (settingsError) throw settingsError;
	if (closureError) throw closureError;
	if (!organization) return null;

	return {
		organization,
		state,
		settings,
		closure: closure ?? null
	};
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	try {
		const state = await getCommercialState(parsedId.data);
		return state ? json(state) : json({ error: 'Organization was not found.' }, { status: 404 });
	} catch (error) {
		console.error('Could not load organization commercial access.', error);
		return json({ error: 'Commercial access could not be loaded.' }, { status: 500 });
	}
};
