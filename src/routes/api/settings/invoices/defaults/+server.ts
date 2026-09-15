import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { invoiceTermWriteError } from '$lib/server/settings/errors';
import { invoiceDefaultsSchema } from '$lib/server/validation/settings.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.invoices.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-invoices-defaults:${organizationId}`,
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

	const parsed = invoiceDefaultsSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('set_organization_invoice_defaults', {
		target_organization_id: organizationId,
		expected_revision: parsed.data.expected_revision,
		new_residential_term_id: parsed.data.residential_term_id,
		new_commercial_term_id: parsed.data.commercial_term_id
	});

	if (error) return invoiceTermWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
