import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireClientPermission } from '$lib/server/access/clients';
import { databaseError, validationError } from '$lib/server/api/errors';
import { propertySchema, zodFieldErrors } from '$lib/server/validation/foundation.schema';

export const POST: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'property.manage');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = propertySchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const organizationId = access.auth.organization.id;
	const { data: client, error: clientError } = await event.locals.supabase
		.from('clients')
		.select('id')
		.eq('id', parsed.data.client_id)
		.eq('organization_id', organizationId)
		.is('deleted_at', null)
		.maybeSingle();
	if (clientError || !client)
		return validationError({ client_id: 'Choose a client in your organization.' });

	const { label, address_line2, state_region, postal_code, access_notes, ...rest } = parsed.data;

	// The database promotes the first active property to primary, so nothing is set here.
	const { data, error } = await event.locals.supabase
		.from('properties')
		.insert({
			organization_id: organizationId,
			...rest,
			// Naming a property is optional. Left blank it takes the street, which is what the office would
			// have typed anyway and reads better in a list than a stock "Primary property".
			label: label?.trim() || rest.address_line1.trim().slice(0, 120),
			address_line2: address_line2?.trim() || null,
			state_region: state_region?.trim() || null,
			postal_code: postal_code?.trim() || null,
			access_notes: access_notes?.trim() || null
		})
		.select()
		.single();

	if (error) return databaseError();
	return json({ property: data }, { status: 201 });
};
