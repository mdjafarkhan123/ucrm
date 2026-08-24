import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';

// How many Properties would follow a changed Business default for future documents — dialog content for
// the confirmation, fetched only when a person is about to change the default.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.taxes.manage');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc(
		'organization_tax_default_property_count',
		{
			target_organization_id: check.auth.organization.id
		}
	);

	if (error) return databaseError();
	return json({ count: data ?? 0 }, { headers: PRIVATE_READ_HEADERS });
};
