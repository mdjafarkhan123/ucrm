import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { taxRateWriteError } from '$lib/server/settings/errors';
import { taxRateDeleteSchema, taxRateUpdateSchema } from '$lib/server/validation/settings.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.taxes.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-taxes-update:${organizationId}`,
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

	const parsed = taxRateUpdateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('update_organization_tax_rate', {
		target_organization_id: organizationId,
		target_rate_id: event.params.id,
		expected_revision: parsed.data.expected_revision,
		new_name: parsed.data.name,
		new_rate_basis_points: parsed.data.rate_basis_points
	});

	if (error) return taxRateWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};

// A rate pinned to any Property cannot be permanently deleted — the command itself refuses with the count,
// which lands here as a 23514 carrying that exact sentence.
export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.taxes.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-taxes-delete:${organizationId}`,
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

	const parsed = taxRateDeleteSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('delete_organization_tax_rate', {
		target_organization_id: organizationId,
		target_rate_id: event.params.id,
		expected_revision: parsed.data.expected_revision
	});

	if (error) return taxRateWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
