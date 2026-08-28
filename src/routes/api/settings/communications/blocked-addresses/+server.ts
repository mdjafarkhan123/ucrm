import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

const noStore = { 'Cache-Control': 'no-store' };

// Every address currently blocked for this organization, plus a short tail of recently cleared ones.
// The suppression tables carry no `authenticated` grant (Part 7.1), so this reads through the
// service-role client with an explicit organization filter rather than RLS.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const { data, error } = await getOwnerSupabaseClient().rpc(
		'get_communication_email_blocked_addresses',
		{ p_organization_id: check.auth.organization.id }
	);
	if (error) {
		console.error('Could not load blocked email addresses.', error);
		return json(
			{ error: 'Blocked addresses could not be loaded.' },
			{ status: 500, headers: noStore }
		);
	}

	return json(data, { headers: noStore });
};
