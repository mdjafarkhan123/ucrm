import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	requireLinkedEntityAccess,
	linkedEntityBelongsToOrganization
} from '$lib/server/access/collaboration';
import { databaseError, validationError } from '$lib/server/api/errors';
import { propertyContactSchema } from '$lib/server/validation/collaboration.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

export const POST: RequestHandler = async (event) => {
	const access = await requireLinkedEntityAccess(event, 'property', 'manage');
	if ('response' in access) return access.response;

	const propertyId = event.params.id;
	const organizationId = access.auth.organization.id;
	const belongs = await linkedEntityBelongsToOrganization(
		event.locals.supabase,
		organizationId,
		'property',
		propertyId
	);
	if (!belongs) return json({ error: 'That property was not found.' }, { status: 404 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = propertyContactSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase
		.from('property_contacts')
		.insert({
			organization_id: organizationId,
			property_id: propertyId,
			first_name: parsed.data.first_name || null,
			last_name: parsed.data.last_name || null,
			role_label: parsed.data.role_label || null,
			is_primary: parsed.data.is_primary
		})
		.select()
		.single();
	if (error) {
		if (error.code === '23505')
			return validationError({ is_primary: 'This property already has a primary contact.' });
		return databaseError();
	}

	return json({ property_contact: data }, { status: 201 });
};

export const GET: RequestHandler = async (event) => {
	const access = await requireLinkedEntityAccess(event, 'property', 'view');
	if ('response' in access) return access.response;

	const { data, error } = await event.locals.supabase
		.from('property_contacts')
		.select('*')
		.eq('property_id', event.params.id)
		.order('is_primary', { ascending: false })
		.order('created_at', { ascending: true });
	if (error) return databaseError();

	return json({ property_contacts: data ?? [] });
};
