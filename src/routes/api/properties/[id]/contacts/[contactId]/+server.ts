import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireLinkedEntityAccess } from '$lib/server/access/collaboration';
import { databaseError, validationError } from '$lib/server/api/errors';
import { propertyContactUpdateSchema } from '$lib/server/validation/collaboration.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

export const PATCH: RequestHandler = async (event) => {
	const access = await requireLinkedEntityAccess(event, 'property', 'manage');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = propertyContactUpdateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const update: Record<string, unknown> = { ...parsed.data };
	if ('first_name' in update) update.first_name = update.first_name || null;
	if ('last_name' in update) update.last_name = update.last_name || null;
	if ('role_label' in update) update.role_label = update.role_label || null;

	const { data, error } = await event.locals.supabase
		.from('property_contacts')
		.update(update)
		.eq('id', event.params.contactId)
		.eq('property_id', event.params.id)
		.select()
		.maybeSingle();
	if (error) {
		if (error.code === '23505')
			return validationError({ is_primary: 'This property already has a primary contact.' });
		return databaseError();
	}
	if (!data) return json({ error: 'That property contact was not found.' }, { status: 404 });

	return json({ property_contact: data });
};

export const DELETE: RequestHandler = async (event) => {
	const access = await requireLinkedEntityAccess(event, 'property', 'manage');
	if ('response' in access) return access.response;

	const { data, error } = await event.locals.supabase
		.from('property_contacts')
		.delete()
		.eq('id', event.params.contactId)
		.eq('property_id', event.params.id)
		.select('id')
		.maybeSingle();
	if (error) return databaseError();
	if (!data) return json({ error: 'That property contact was not found.' }, { status: 404 });

	return json({ deleted: true });
};
