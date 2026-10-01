import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { requireSupportMember } from '$lib/server/support/access';
import type { SupportUnread } from '$lib/support/api';

// How many of Uplift's messages the signed-in member has not seen yet: the badge on Chat with Uplift.
export const GET: RequestHandler = async (event) => {
	const check = await requireSupportMember(event);
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('support_unread_count', {
		target_organization_id: check.auth.organization.id
	});
	if (error) return databaseError();

	const unread: SupportUnread = { unread: data ?? 0 };
	return json(unread, { headers: PRIVATE_READ_HEADERS });
};
