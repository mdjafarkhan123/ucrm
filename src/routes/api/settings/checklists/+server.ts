import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { checklistReadError, checklistWriteError } from '$lib/server/checklists/errors';
import { checklistTemplateCreateSchema } from '$lib/server/validation/checklists.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

// The Settings library. Read by anyone in the business, because the attach picker on a job and the crew
// filling in a form both need the questions; only building one is gated, by the command itself.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('checklist_templates_list', {
		target_organization_id: check.auth.organization.id,
		include_archived: event.url.searchParams.get('archived') === 'true'
	});

	if (error) return checklistReadError(error);
	return json(data, { headers: PRIVATE_READ_HEADERS });
};

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.checklists.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-checklists-create:${organizationId}`,
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

	const parsed = checklistTemplateCreateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('create_checklist_template', {
		target_organization_id: organizationId,
		name: parsed.data.name,
		items: parsed.data.items
	});

	if (error) return checklistWriteError(error);
	return json(data, { status: 201, headers: NO_STORE_HEADERS });
};
