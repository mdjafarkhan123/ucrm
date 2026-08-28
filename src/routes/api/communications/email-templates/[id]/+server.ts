import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { emailTemplateWriteError } from '$lib/server/communications/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { emailTemplateUpdateSchema } from '$lib/server/validation/communications.schema';

const TEMPLATE_SELECT =
	'id, folder, name, subject, body, source_template_id, source_version_copied_at, created_at, updated_at';
const NOT_FOUND = 'That email template could not be found.';
const WRITE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

// Editing an org template never touches source_version_copied_at -- that column only moves through the
// dedicated adopt action, so an edit can never accidentally mark a template as caught up with the library.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.send');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `communications-email-templates-update:${organizationId}`,
			...WRITE_LIMIT
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

	const parsed = emailTemplateUpdateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const changes: Record<string, unknown> = {};
	for (const [key, value] of Object.entries(parsed.data)) {
		if (value !== undefined) changes[key] = value;
	}

	const { data, error } = await event.locals.supabase
		.from('communications_email_templates')
		.update(changes)
		.eq('organization_id', organizationId)
		.eq('id', event.params.id)
		.select(TEMPLATE_SELECT)
		.maybeSingle();

	if (error) return emailTemplateWriteError(error);
	if (!data) return notFound(NOT_FOUND);
	return json({ item: data }, { headers: NO_STORE_HEADERS });
};

// Real delete, not archive. A template's text is copied into the composer at insert time, never referenced
// live by an already-sent message, so there is nothing downstream to preserve a reference for.
export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.send');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `communications-email-templates-delete:${organizationId}`,
			...WRITE_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	const { data, error } = await event.locals.supabase
		.from('communications_email_templates')
		.delete()
		.eq('organization_id', organizationId)
		.eq('id', event.params.id)
		.select('id')
		.maybeSingle();

	if (error) return emailTemplateWriteError(error);
	if (!data) return notFound(NOT_FOUND);
	return json({ status: 'deleted', id: data.id }, { headers: NO_STORE_HEADERS });
};
