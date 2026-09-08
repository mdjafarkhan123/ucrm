import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { checklistWriteError } from '$lib/server/checklists/errors';
import {
	checklistTemplateArchiveSchema,
	checklistTemplateUpdateSchema
} from '$lib/server/validation/checklists.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

// Editing replaces the name and the whole question list at once. Jobs that already carry this checklist
// keep the copy they were given; the count of those jobs comes back so the screen can say so.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.checklists.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-checklists-update:${organizationId}`,
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

	const parsed = checklistTemplateUpdateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('update_checklist_template', {
		target_organization_id: organizationId,
		target_template_id: event.params.id,
		name: parsed.data.name,
		items: parsed.data.items
	});

	if (error) return checklistWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};

// Archive and restore. Never a delete: the jobs that used this checklist keep pointing at where their
// questions came from.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.checklists.manage');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = checklistTemplateArchiveSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('set_checklist_template_archived', {
		target_organization_id: check.auth.organization.id,
		target_template_id: event.params.id,
		archived: parsed.data.archived
	});

	if (error) return checklistWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
