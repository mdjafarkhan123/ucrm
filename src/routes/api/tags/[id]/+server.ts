import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { z } from 'zod';
import { requireClientPermission } from '$lib/server/access/clients';
import { databaseError, validationError } from '$lib/server/api/errors';
import { tagColorUpdateSchema } from '$lib/server/validation/collaboration.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
export const PATCH: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.edit');
	if ('response' in access) return access.response;
	if (!z.string().uuid().safeParse(event.params.id).success)
		return validationError({ id: 'Choose a tag.' });
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = tagColorUpdateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));
	const { data, error } = await event.locals.supabase
		.from('tags')
		.update(parsed.data)
		.eq('id', event.params.id)
		.eq('organization_id', access.auth.organization.id)
		.select()
		.maybeSingle();
	if (error) return databaseError();
	if (!data) return json({ error: 'Tag not found.' }, { status: 404 });
	return json({ tag: data });
};
