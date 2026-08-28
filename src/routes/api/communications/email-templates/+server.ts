import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	requireOrganizationAdmin,
	requireOrganizationPermission
} from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import { encodeCursor, quoteFilterValue, readCursor } from '$lib/server/api/keyset';
import { emailTemplateWriteError } from '$lib/server/communications/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	emailTemplateCopySchema,
	emailTemplateCreateSchema,
	emailTemplateListQuerySchema
} from '$lib/server/validation/communications.schema';

const TEMPLATE_SELECT =
	'id, folder, name, subject, body, source_template_id, source_version_copied_at, created_at, updated_at';
const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

// The org's own library, alphabetical by name -- what both the Settings list and the composer picker want.
// `conversations.send` gates reading it the same way it gates sending itself: a template is only useful to
// someone who can compose a message.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.send');
	if ('response' in check) return check.response;

	const parsed = emailTemplateListQuerySchema.safeParse(
		Object.fromEntries(event.url.searchParams.entries())
	);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));
	const query = parsed.data;

	let items = event.locals.supabase
		.from('communications_email_templates')
		.select(TEMPLATE_SELECT)
		.eq('organization_id', check.auth.organization.id);

	if (query.folder) items = items.eq('folder', query.folder);
	if (query.search) {
		// Unindexed ILIKE on purpose, matching Snippets' own search: a business's template library is a
		// bounded, per-tenant handful of rows, not a corpus that needs trigram or full-text support.
		const escaped = query.search.replace(/[\\%_]/g, (match) => `\\${match}`);
		items = items.or(`name.ilike.%${escaped}%,subject.ilike.%${escaped}%`);
	}

	const cursor = readCursor(query.cursor);
	if (cursor) {
		const quoted = quoteFilterValue(cursor.value);
		items = items
			.gte('name', cursor.value)
			.or(`name.gt.${quoted},and(name.eq.${quoted},id.gt.${cursor.id})`);
	}

	// One extra row answers "is there another page" without a second count query.
	const { data: rows, error } = await items
		.order('name', { ascending: true })
		.order('id', { ascending: true })
		.limit(query.limit + 1);
	if (error) return databaseError();

	const page = (rows ?? []).slice(0, query.limit);

	// One batched lookup answers "is a newer platform version available" for every copied template on this
	// page, instead of the settings screen opening the whole library just to compare versions.
	const sourceIds = [
		...new Set(page.map((row) => row.source_template_id).filter((id) => id !== null))
	];
	const currentVersionByTemplate = new Map<string, number>();
	if (sourceIds.length > 0) {
		const { data: sources, error: sourceError } = await getOwnerSupabaseClient()
			.from('platform_email_templates')
			.select('id, version')
			.in('id', sourceIds);
		if (sourceError) return databaseError();
		for (const source of sources ?? []) currentVersionByTemplate.set(source.id, source.version);
	}

	const last = page.at(-1) as { name: string; id: string } | undefined;
	return json(
		{
			items: page.map((row) => ({
				...row,
				update_available: row.source_template_id
					? currentVersionByTemplate.get(row.source_template_id) !== row.source_version_copied_at
					: false
			})),
			next_cursor:
				(rows ?? []).length > query.limit && last ? encodeCursor(last.name, last.id) : null
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// Two shapes share this endpoint: a template written from scratch, or a copy of a platform template. Only
// `source_template_id` tells them apart -- its presence is checked on the raw body before either schema
// runs, same branch-then-validate shape the Snippets route doesn't need because it only ever has one shape.
// Owners/admins only: a template is shared across the whole team, unlike a personal Snippet.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.send');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `communications-email-templates-create:${organizationId}`,
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

	const isCopy = typeof body === 'object' && body !== null && 'source_template_id' in body;

	if (isCopy) {
		const parsed = emailTemplateCopySchema.safeParse(body);
		if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

		// Platform templates carry no authenticated RLS policy (owner-only) -- the org-side read is this
		// route's job, filtered to what the org's current package actually includes.
		const owner = getOwnerSupabaseClient();
		const [{ data: source, error: sourceError }, { data: visibility, error: visibilityError }] =
			await Promise.all([
				owner
					.from('platform_email_templates')
					.select('id, name, subject, body, version')
					.eq('id', parsed.data.source_template_id)
					.maybeSingle(),
				owner
					.from('platform_email_template_packages')
					.select('package_key')
					.eq('template_id', parsed.data.source_template_id)
			]);
		if (sourceError) return databaseError();
		if (visibilityError) return databaseError();
		if (!source) return json({ error: 'Unknown email template.' }, { status: 404 });

		const restrictedTo = (visibility ?? []).map((row) => row.package_key);
		const visibleToOrg =
			restrictedTo.length === 0 || restrictedTo.includes(check.access.package.effective_key);
		if (!visibleToOrg) return json({ error: 'Unknown email template.' }, { status: 404 });

		const { data, error } = await event.locals.supabase
			.from('communications_email_templates')
			.insert({
				organization_id: organizationId,
				created_by: check.auth.user.id,
				source_template_id: source.id,
				source_version_copied_at: source.version,
				folder: parsed.data.folder,
				name: source.name,
				subject: source.subject,
				body: source.body
			})
			.select(TEMPLATE_SELECT)
			.single();

		if (error) return emailTemplateWriteError(error);
		return json({ item: data }, { status: 201, headers: NO_STORE_HEADERS });
	}

	const parsed = emailTemplateCreateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase
		.from('communications_email_templates')
		.insert({
			organization_id: organizationId,
			created_by: check.auth.user.id,
			source_template_id: null,
			source_version_copied_at: null,
			...parsed.data
		})
		.select(TEMPLATE_SELECT)
		.single();

	if (error) return emailTemplateWriteError(error);
	return json({ item: data }, { status: 201, headers: NO_STORE_HEADERS });
};
