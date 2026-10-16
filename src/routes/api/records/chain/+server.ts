import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOrganizationContext } from '$lib/server/auth/organization';
import {
	PRIVATE_READ_HEADERS,
	databaseError,
	unauthorized,
	validationError
} from '$lib/server/api/errors';

// Where a request, quote, job or invoice stands on the line Request > Quote > Job > Invoice > Paid, for the
// progress strip at the top of each record page. One database call follows the links and checks, step by
// step, that this member may open each record (see record_chain), so a step they cannot open comes back as
// "restricted" rather than with its details. Whoever may open the record the page stands on may ask.
const chainQuerySchema = z.object({
	kind: z.enum(['request', 'quote', 'job', 'invoice']),
	id: z.string().uuid()
});

export const GET: RequestHandler = async (event) => {
	const parsed = chainQuerySchema.safeParse(Object.fromEntries(event.url.searchParams.entries()));
	if (!parsed.success) return validationError({ id: 'That record could not be found.' });

	const auth = await getOrganizationContext(event);
	if (!auth) return unauthorized();

	const { data, error } = await event.locals.supabase.rpc('record_chain', {
		target_organization_id: auth.organization.id,
		source_kind: parsed.data.kind,
		source_id: parsed.data.id
	});
	if (error) return databaseError();

	return json(
		{ chain: data ?? { request: null, quote: null, job: null, invoices: null } },
		{ headers: PRIVATE_READ_HEADERS }
	);
};
