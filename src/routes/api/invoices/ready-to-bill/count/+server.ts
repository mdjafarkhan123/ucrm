import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';

// The number on the "Ready to bill" button. Counted over exactly the predicate the queue pages through, so
// the badge and the rows behind it can never disagree. The function returns 0 rather than refusing when the
// member may not bill, so the button simply does not appear for them.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('ready_to_bill_count', {
		target_organization_id: check.auth.organization.id
	});
	if (error) return databaseError();

	return json({ count: Number(data ?? 0) }, { headers: PRIVATE_READ_HEADERS });
};
