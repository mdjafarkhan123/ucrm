import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { requireSetupEditor, setupWriteError, setupWriteLimited } from '$lib/server/setup/access';

// Records that the welcome has been shown, so it greets the administrator once. No body: there is nothing
// to choose, only the fact that it happened.
export const POST: RequestHandler = async (event) => {
	const check = await requireSetupEditor(event);
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const limited = await setupWriteLimited(event, organizationId);
	if (limited) return limited;

	const { data, error } = await event.locals.supabase.rpc('mark_organization_setup_welcome_seen', {
		target_organization_id: organizationId
	});
	if (error) return setupWriteError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
