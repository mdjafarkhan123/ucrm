import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import { databaseError, validationError } from '$lib/server/api/errors';
import { contactSchema, zodFieldErrors } from '$lib/server/validation/foundation.schema';

export const POST: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth)
		return new Response(
			JSON.stringify({ error: 'Authentication or organization membership required' }),
			{ status: 401, headers: { 'content-type': 'application/json' } }
		);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = contactSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase
		.from('contacts')
		.insert({ organization_id: auth.organization.id, ...parsed.data })
		.select()
		.single();

	if (error) return databaseError();
	return json({ contact: data }, { status: 201 });
};
