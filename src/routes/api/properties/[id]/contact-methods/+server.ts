import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	requireLinkedEntityAccess,
	linkedEntityBelongsToOrganization
} from '$lib/server/access/collaboration';
import { databaseError, validationError } from '$lib/server/api/errors';
import { propertyContactMethodSchema } from '$lib/server/validation/collaboration.schema';
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

	const parsed = propertyContactMethodSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	if (parsed.data.property_contact_id) {
		const { data: contact } = await event.locals.supabase
			.from('property_contacts')
			.select('id')
			.eq('id', parsed.data.property_contact_id)
			.eq('property_id', propertyId)
			.maybeSingle();
		if (!contact)
			return validationError({ property_contact_id: 'Choose a contact on this property.' });
	}

	const { data, error } = await event.locals.supabase
		.from('property_contact_methods')
		.insert({
			organization_id: organizationId,
			property_id: propertyId,
			property_contact_id: parsed.data.property_contact_id ?? null,
			kind: parsed.data.kind,
			value: parsed.data.value,
			label: parsed.data.label || null,
			is_primary: parsed.data.is_primary
		})
		.select()
		.single();
	if (error) {
		if (error.code === '23505')
			return validationError({ value: 'That contact method already exists for this property.' });
		return databaseError();
	}

	return json({ property_contact_method: data }, { status: 201 });
};

export const GET: RequestHandler = async (event) => {
	const access = await requireLinkedEntityAccess(event, 'property', 'view');
	if ('response' in access) return access.response;

	const { data, error } = await event.locals.supabase
		.from('property_contact_methods')
		.select('*')
		.eq('property_id', event.params.id)
		.order('is_primary', { ascending: false })
		.order('created_at', { ascending: true });
	if (error) return databaseError();

	return json({ property_contact_methods: data ?? [] });
};
