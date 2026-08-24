import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, notFound } from '$lib/server/api/errors';
import { streamOrganizationLogo } from '$lib/server/settings/logo';

// One permanent URL for the business logo, so the sidebar can point at it with a plain `<img src>`. A
// presigned storage link cannot do this job: it dies in five minutes, so every page left open would go
// broken. Customer documents get their own token-scoped route; this one is for people signed in.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.business.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase
		.from('organization_settings')
		.select('logo_object_key')
		.eq('organization_id', check.auth.organization.id)
		.maybeSingle();
	if (error) return databaseError();
	if (!data?.logo_object_key) return notFound('No logo has been uploaded yet.');

	return streamOrganizationLogo(data.logo_object_key, event.request.headers.get('if-none-match'));
};
