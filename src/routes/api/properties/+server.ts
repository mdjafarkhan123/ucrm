import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import { databaseError, validationError } from '$lib/server/api/errors';
import { propertySchema, zodFieldErrors } from '$lib/server/validation/foundation.schema';

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

	const parsed = propertySchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const organizationId = auth.organization.id;
	const { data: contact, error: contactError } = await event.locals.supabase
		.from('contacts')
		.select('id')
		.eq('id', parsed.data.contact_id)
		.eq('organization_id', organizationId)
		.maybeSingle();
	if (contactError || !contact)
		return validationError({ contact_id: 'Choose a customer in your organization.' });

	const { data, error } = await event.locals.supabase
		.from('properties')
		.insert({ organization_id: organizationId, ...parsed.data })
		.select()
		.single();

	if (error) return databaseError();
	return json({ property: data }, { status: 201 });
};
