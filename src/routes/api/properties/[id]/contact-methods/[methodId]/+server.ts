import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireLinkedEntityAccess } from '$lib/server/access/collaboration';
import { databaseError, validationError } from '$lib/server/api/errors';
import {
	propertyContactMethodUpdateSchema,
	validContactMethodValue
} from '$lib/server/validation/collaboration.schema';
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

	const parsed = propertyContactMethodUpdateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	if (parsed.data.value !== undefined) {
		const { data: existing } = await event.locals.supabase
			.from('property_contact_methods')
			.select('kind')
			.eq('id', event.params.methodId)
			.eq('property_id', event.params.id)
			.maybeSingle();
		if (!existing) return json({ error: 'That contact method was not found.' }, { status: 404 });
		if (!validContactMethodValue(existing.kind as 'email' | 'phone', parsed.data.value))
			return validationError({ value: 'Enter a valid email or phone number.' });
	}

	const update: Record<string, unknown> = { ...parsed.data };
	if ('label' in update) update.label = update.label || null;

	const { data, error } = await event.locals.supabase
		.from('property_contact_methods')
		.update(update)
		.eq('id', event.params.methodId)
		.eq('property_id', event.params.id)
		.select()
		.maybeSingle();
	if (error) {
		if (error.code === '23505')
			return validationError({ value: 'That contact method already exists for this property.' });
		return databaseError();
	}
	if (!data) return json({ error: 'That contact method was not found.' }, { status: 404 });

	return json({ property_contact_method: data });
};

export const DELETE: RequestHandler = async (event) => {
	const access = await requireLinkedEntityAccess(event, 'property', 'manage');
	if ('response' in access) return access.response;

	const { data, error } = await event.locals.supabase
		.from('property_contact_methods')
		.delete()
		.eq('id', event.params.methodId)
		.eq('property_id', event.params.id)
		.select('id')
		.maybeSingle();
	if (error) return databaseError();
	if (!data) return json({ error: 'That contact method was not found.' }, { status: 404 });

	return json({ deleted: true });
};
