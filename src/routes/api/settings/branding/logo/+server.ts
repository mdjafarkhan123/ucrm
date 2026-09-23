import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { settingsWriteError } from '$lib/server/settings/errors';

const LOGO_LIMIT = { windowSeconds: 60, maxAttempts: 10 };

export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.business.edit');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-logo-commit:${organizationId}`,
			...LOGO_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	const { data, error } = await event.locals.supabase.rpc('remove_organization_logo', {
		target_organization_id: organizationId
	});
	if (error) return settingsWriteError(error);

	const result = data as { branding_revision: number };

	return json(
		{ branding_revision: result.branding_revision, logo_url: null },
		{ headers: NO_STORE_HEADERS }
	);
};
