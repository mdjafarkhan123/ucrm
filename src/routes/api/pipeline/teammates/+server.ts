import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';

// Who a card or Task can be given to, who the Salesperson filter lists, and who can be @mentioned in a
// Brief Note: active teammates who may see the Pipeline, so nobody is offered who would be refused or sent
// a link they cannot open (Pipedrive and HubSpot only offer people with access). Named by their name, else
// their sign-in email. Anyone who can see the board may read it, because the filter is theirs too.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('pipeline_mentionable_teammates', {
		target_organization_id: check.auth.organization.id
	});
	if (error) return databaseError();

	const rows = (data ?? []) as {
		user_id: string;
		full_name: string | null;
		avatar_url: string | null;
	}[];
	const members = rows.map((member) => ({
		id: member.user_id,
		full_name: member.full_name,
		avatar_url: member.avatar_url
	}));
	return json({ members }, { headers: PRIVATE_READ_HEADERS });
};
