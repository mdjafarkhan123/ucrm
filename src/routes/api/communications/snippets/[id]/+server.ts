import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { snippetWriteError } from '$lib/server/communications/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { communicationSnippetUpdateSchema } from '$lib/server/validation/communications.schema';

const SNIPPET_SELECT = 'id, folder, title, body, created_at, updated_at';
const NOT_FOUND = 'That snippet could not be found.';
const WRITE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

// Editing changes only what a future insert copies -- any message a snippet already went into keeps its
// own copy of the old text untouched.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.send');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `communications-snippets-update:${organizationId}`,
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

	const parsed = communicationSnippetUpdateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const changes: Record<string, unknown> = {};
	for (const [key, value] of Object.entries(parsed.data)) {
		if (value !== undefined) changes[key] = value;
	}

	const { data, error } = await event.locals.supabase
		.from('communications_snippets')
		.update(changes)
		.eq('organization_id', organizationId)
		.eq('id', event.params.id)
		.select(SNIPPET_SELECT)
		.maybeSingle();

	if (error) return snippetWriteError(error);
	if (!data) return notFound(NOT_FOUND);
	return json({ item: data }, { headers: NO_STORE_HEADERS });
};

// Real delete, not archive. A snippet is a reusable draft, never something a sent message points back at,
// so there is nothing downstream to preserve a reference for.
export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.send');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `communications-snippets-delete:${organizationId}`,
			...WRITE_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	const { data, error } = await event.locals.supabase
		.from('communications_snippets')
		.delete()
		.eq('organization_id', organizationId)
		.eq('id', event.params.id)
		.select('id')
		.maybeSingle();

	if (error) return snippetWriteError(error);
	if (!data) return notFound(NOT_FOUND);
	return json({ status: 'deleted', id: data.id }, { headers: NO_STORE_HEADERS });
};
