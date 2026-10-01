import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';

// The lead sources on this organization's open cards, for the board's Lead source list. Clients carry
// their source as free text, so the list has to come from the records: the client form's own list alone
// would leave a card marked "Google" or "staff" impossible to filter to. Each source appears once however
// it is capitalised, spelled the way most of those clients spell it.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('pipeline_lead_sources', {
		target_organization_id: check.auth.organization.id
	});
	if (error) return databaseError();

	return json(
		{ lead_sources: ((data ?? []) as { lead_source: string }[]).map((row) => row.lead_source) },
		{ headers: PRIVATE_READ_HEADERS }
	);
};
