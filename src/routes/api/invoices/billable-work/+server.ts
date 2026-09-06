import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

const querySchema = z.object({
	client_id: z.string().uuid('Choose a client to continue.')
});

// What work is waiting to be billed for one client — the list behind the "select work to invoice" picker.
//
// The read is `public.client_billable_work`, which checks invoices.create and jobs.view_price for itself and
// excludes anything an invoice has already claimed. Scoped to one client and capped in the database, so this
// route never returns an unbounded page and needs no pagination of its own.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.create');
	if ('response' in check) return check.response;

	const parsed = querySchema.safeParse(Object.fromEntries(event.url.searchParams.entries()));
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('client_billable_work', {
		target_organization_id: check.auth.organization.id,
		target_client_id: parsed.data.client_id
	});
	if (error) return databaseError();

	return json({ work: data ?? [] }, { headers: PRIVATE_READ_HEADERS });
};
