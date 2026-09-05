import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';

// The organization's named payment terms, for the invoice form's Terms picker. These are not money, so an
// ordinary security-invoker read under the table's own membership RLS is enough — no definer function needed.
// The form offers these plus "Client's default" (send no term and the command resolves the client/account
// default) and "Custom date". Archived terms are kept as history and left out here.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase
		.from('invoice_payment_terms')
		.select('id, name, rule, net_days, is_protected')
		.eq('organization_id', check.auth.organization.id)
		.is('archived_at', null)
		.order('position', { ascending: true })
		.order('name', { ascending: true });

	if (error) return databaseError();

	return json({ terms: data ?? [] }, { headers: PRIVATE_READ_HEADERS });
};
