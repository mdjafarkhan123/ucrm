import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { taxRateWriteError } from '$lib/server/settings/errors';
import { taxRateActiveSchema } from '$lib/server/validation/settings.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

// Inactive drops a rate from new selections without touching the Properties already pinned to it — the
// same command in reverse reactivates it. Never a delete, so it carries no property-count refusal.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.taxes.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-taxes-active:${organizationId}`,
			...SAVE_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = taxRateActiveSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('set_organization_tax_rate_active', {
		target_organization_id: organizationId,
		target_rate_id: event.params.id,
		expected_revision: parsed.data.expected_revision,
		new_is_active: parsed.data.is_active
	});

	if (error) return taxRateWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
