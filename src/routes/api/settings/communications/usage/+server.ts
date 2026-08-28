import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

const noStore = { 'Cache-Control': 'no-store' };

// This billing period's email allowance standing for the signed-in organization. The allowance,
// usage, and alert tables carry no `authenticated` grant (Part 7), so this reads through the
// service-role client with an explicit organization filter rather than RLS.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const { data, error } = await getOwnerSupabaseClient().rpc(
		'get_organization_communication_email_usage',
		{ p_organization_id: check.auth.organization.id }
	);
	if (error) {
		console.error('Could not load the email allowance usage.', error);
		return json({ error: 'Email usage could not be loaded.' }, { status: 500, headers: noStore });
	}

	return json(data?.[0] ?? null, { headers: noStore });
};
