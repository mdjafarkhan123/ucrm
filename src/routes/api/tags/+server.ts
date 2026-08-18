import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import { requireClientPermission } from '$lib/server/access/clients';
import { databaseError, validationError } from '$lib/server/api/errors';
import { tagCreateSchema } from '$lib/server/validation/collaboration.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

export const POST: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.edit');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = tagCreateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase
		.from('tags')
		.insert({ organization_id: access.auth.organization.id, ...parsed.data })
		.select()
		.single();
	if (error) {
		if (error.code === '23505') return validationError({ name: 'That tag already exists.' });
		return databaseError();
	}

	return json({ tag: data }, { status: 201 });
};

// The tag catalog is org-wide and visible to any member, matching the "members can view tags" RLS policy.
export const GET: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth)
		return json({ error: 'Authentication or organization membership required.' }, { status: 401 });

	const { data, error } = await event.locals.supabase
		.from('tags')
		.select('*')
		.order('name', { ascending: true });
	if (error) return databaseError();

	return json({ tags: data ?? [] });
};
