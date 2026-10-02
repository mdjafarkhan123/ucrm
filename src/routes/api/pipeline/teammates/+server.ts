import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';

// Who can be @mentioned in a Brief Note: active teammates who may see the Pipeline, so a mention never
// sends someone a link they cannot open (Pipedrive and HubSpot only offer people with access). Named the
// way the Task owner list names them -- their name, else their sign-in email.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.edit');
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
