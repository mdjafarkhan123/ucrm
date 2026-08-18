import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, Tables } from '$lib/database.types';
import {
	requireLinkedEntityAccess,
	linkedEntityBelongsToOrganization,
	parseLinkedEntityQuery
} from '$lib/server/access/collaboration';
import { requireClientPermission } from '$lib/server/access/clients';
import { databaseError, validationError } from '$lib/server/api/errors';
import { tagAssignmentCreateSchema } from '$lib/server/validation/collaboration.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

export const POST: RequestHandler = async (event) => {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = tagAssignmentCreateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const access = await requireLinkedEntityAccess(event, parsed.data.entity_type, 'manage');
	if ('response' in access) return access.response;

	// The tag catalog is organization-wide, so adding a name to it needs the same permission POST /api/tags
	// asks for. Managing a Property's own tags rides property.manage, which is not the same thing.
	if (parsed.data.tag_name && parsed.data.entity_type !== 'client') {
		const catalogAccess = await requireClientPermission(event, 'customers.edit');
		if ('response' in catalogAccess) return catalogAccess.response;
	}

	const organizationId = access.auth.organization.id;
	const belongs = await linkedEntityBelongsToOrganization(
		event.locals.supabase,
		organizationId,
		parsed.data.entity_type,
		parsed.data.entity_id
	);
	if (!belongs) return validationError({ entity_id: 'That record was not found.' });

	const resolved = await resolveTag(event.locals.supabase, organizationId, parsed.data);
	if ('fieldErrors' in resolved) return validationError(resolved.fieldErrors);
	if ('failed' in resolved) return databaseError();
	const tag = resolved.tag;

	const { data, error } = await event.locals.supabase
		.from('tag_assignments')
		.insert({
			organization_id: organizationId,
			created_by: access.auth.user.id,
			tag_id: tag.id,
			entity_type: parsed.data.entity_type,
			entity_id: parsed.data.entity_id
		})
		.select()
		.single();

	if (error) {
		// Already applied. Returning the existing row keeps a repeated click (or a retried request)
		// harmless instead of surfacing an error for a state the caller already wanted.
		if (error.code === '23505') {
			const { data: existing } = await event.locals.supabase
				.from('tag_assignments')
				.select('*')
				.eq('tag_id', tag.id)
				.eq('entity_type', parsed.data.entity_type)
				.eq('entity_id', parsed.data.entity_id)
				.maybeSingle();
			if (existing) return json({ assignment: { ...existing, tag } });
		}
		return databaseError();
	}

	// The tag travels with the assignment so the browser can render the new chip without a second fetch.
	return json({ assignment: { ...data, tag } }, { status: 201 });
};

type ResolveTagResult =
	| { tag: Tables<'tags'> }
	| { fieldErrors: Record<string, string> }
	| { failed: true };

// Accepts either an existing tag id or a name to find-or-create, so the browser never has to make a
// separate create call before assigning.
async function resolveTag(
	supabase: SupabaseClient<Database>,
	organizationId: string,
	input: { tag_id?: string; tag_name?: string }
): Promise<ResolveTagResult> {
	if (input.tag_id) {
		const { data, error } = await supabase
			.from('tags')
			.select('*')
			.eq('id', input.tag_id)
			.eq('organization_id', organizationId)
			.maybeSingle();
		if (error) return { failed: true };
		if (!data) return { fieldErrors: { tag_id: 'Choose a tag in your organization.' } };
		return { tag: data };
	}

	const name = (input.tag_name ?? '').trim();
	const normalized = name.toLowerCase();

	const { data: existing, error: existingError } = await supabase
		.from('tags')
		.select('*')
		.eq('organization_id', organizationId)
		.eq('normalized_name', normalized)
		.maybeSingle();
	if (existingError) return { failed: true };
	if (existing) return { tag: existing };

	const { data: created, error: createError } = await supabase
		.from('tags')
		.insert({ organization_id: organizationId, name })
		.select()
		.single();
	if (!createError) return { tag: created };

	// Someone else created the same name between the lookup and the insert; use theirs.
	if (createError.code === '23505') {
		const { data: raced } = await supabase
			.from('tags')
			.select('*')
			.eq('organization_id', organizationId)
			.eq('normalized_name', normalized)
			.maybeSingle();
		if (raced) return { tag: raced };
	}
	return { failed: true };
}

export const GET: RequestHandler = async (event) => {
	const params = parseLinkedEntityQuery(event.url);
	if (!params) return validationError({ entity_type: 'Provide entity_type and entity_id.' });

	const access = await requireLinkedEntityAccess(event, params.entity_type, 'view');
	if ('response' in access) return access.response;

	const { data: assignments, error: assignmentsError } = await event.locals.supabase
		.from('tag_assignments')
		.select('*')
		.eq('entity_type', params.entity_type)
		.eq('entity_id', params.entity_id);
	if (assignmentsError) return databaseError();

	const tagIds = [...new Set((assignments ?? []).map((assignment) => assignment.tag_id))];
	if (tagIds.length === 0) return json({ assignments: [] });

	const { data: tags, error: tagsError } = await event.locals.supabase
		.from('tags')
		.select('*')
		.in('id', tagIds);
	if (tagsError) return databaseError();

	const tagById = new Map((tags ?? []).map((tag) => [tag.id, tag]));
	return json({
		assignments: (assignments ?? []).map((assignment) => ({
			...assignment,
			tag: tagById.get(assignment.tag_id) ?? null
		}))
	});
};
