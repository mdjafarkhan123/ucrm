import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import { databaseError, validationError } from '$lib/server/api/errors';
import { profileIdsQuerySchema } from '$lib/server/validation/collaboration.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

// Batch name/avatar lookup for whoever authored a note, uploaded a file, or triggered an activity
// event. RLS on `profiles` only returns the caller's own row plus rows for anyone who shares an
// organization with them, so this never leaks a stranger's profile.
export const GET: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth)
		return json({ error: 'Authentication or organization membership required.' }, { status: 401 });

	const ids = [...new Set(event.url.searchParams.get('ids')?.split(',').filter(Boolean) ?? [])];
	const parsed = profileIdsQuerySchema.safeParse({ ids });
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase
		.from('profiles')
		.select('id, full_name, avatar_url')
		.in('id', parsed.data.ids);
	if (error) return databaseError();

	return json({ profiles: data ?? [] });
};
