import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import { encodeCursor, quoteFilterValue, readCursor } from '$lib/server/api/keyset';
import { snippetWriteError } from '$lib/server/communications/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	communicationSnippetCreateSchema,
	communicationSnippetListQuerySchema
} from '$lib/server/validation/communications.schema';

const SNIPPET_SELECT = 'id, folder, title, body, created_at, updated_at';
const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

// The full org library, alphabetical by title -- what both the Settings list and the composer picker want.
// `conversations.send` gates this the same way it gates sending itself: a snippet is only useful to
// someone who can compose a reply.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.send');
	if ('response' in check) return check.response;

	const parsed = communicationSnippetListQuerySchema.safeParse(
		Object.fromEntries(event.url.searchParams.entries())
	);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));
	const query = parsed.data;

	let items = event.locals.supabase
		.from('communications_snippets')
		.select(SNIPPET_SELECT)
		.eq('organization_id', check.auth.organization.id);

	if (query.folder) items = items.eq('folder', query.folder);
	if (query.search) {
		// Unindexed ILIKE on purpose, matching the Price Book's own search: a business's snippet library is
		// a bounded, per-tenant handful of rows, not a corpus that needs trigram or full-text support.
		const escaped = query.search.replace(/[\\%_]/g, (match) => `\\${match}`);
		items = items.or(`title.ilike.%${escaped}%,body.ilike.%${escaped}%`);
	}

	const cursor = readCursor(query.cursor);
	if (cursor) {
		const quoted = quoteFilterValue(cursor.value);
		items = items
			.gte('title', cursor.value)
			.or(`title.gt.${quoted},and(title.eq.${quoted},id.gt.${cursor.id})`);
	}

	// One extra row answers "is there another page" without a second count query.
	const { data: rows, error } = await items
		.order('title', { ascending: true })
		.order('id', { ascending: true })
		.limit(query.limit + 1);
	if (error) return databaseError();

	const page = (rows ?? []).slice(0, query.limit);
	const last = page.at(-1) as { title: string; id: string } | undefined;
	return json(
		{
			items: page,
			next_cursor:
				(rows ?? []).length > query.limit && last ? encodeCursor(last.title, last.id) : null
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// A new reusable snippet. Nothing already sent changes because of it -- a snippet's text is copied into
// the composer at insert time, never referenced live.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.send');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `communications-snippets-create:${organizationId}`,
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

	const parsed = communicationSnippetCreateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase
		.from('communications_snippets')
		.insert({
			organization_id: organizationId,
			created_by: check.auth.user.id,
			...parsed.data
		})
		.select(SNIPPET_SELECT)
		.single();

	if (error) return snippetWriteError(error);
	return json({ item: data }, { status: 201, headers: NO_STORE_HEADERS });
};
