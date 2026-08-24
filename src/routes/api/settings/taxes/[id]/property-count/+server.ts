import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';

// What an edit or delete confirmation needs before it acts, and nothing else — never property identities.
// Not part of the list read: it is dialog content, fetched only when that dialog is about to open.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.taxes.manage');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('organization_tax_rate_property_count', {
		target_organization_id: check.auth.organization.id,
		target_rate_id: event.params.id
	});

	if (error) return databaseError();
	return json({ count: data ?? 0 }, { headers: PRIVATE_READ_HEADERS });
};
